class AuditViews
  NAMES = %w[
    audit_revenue_by_sub_channel audit_revenue_by_company audit_stalled_companies
    audit_weekly_revenue audit_pending_actions audit_company_ec_divergence
  ].freeze

  # Views recriadas por este serviço; as demais nascem nas migrações que as criaram.
  ALIGNED_VIEWS = %w[
    audit_stalled_companies audit_revenue_by_company audit_revenue_by_sub_channel
  ].freeze

  # Dias sem venda a partir do qual um CNPJ entra no relatório de clientes parados.
  STALLED_THRESHOLD = 7

  def self.refresh!
    connection = ApplicationRecord.connection
    in_transaction = connection.transaction_open?
    NAMES.each do |name|
      concurrently = "CONCURRENTLY " if !in_transaction && populated?(name)
      connection.execute("REFRESH MATERIALIZED VIEW #{concurrently}#{name}")
    end
  end

  # CONCURRENTLY tem duas restrições: não roda dentro de transação (os testes rodam),
  # e não roda em view ainda não populada — o structure.sql as cria WITH NO DATA, então
  # o primeiro refresh de um banco novo é sempre bloqueante.
  def self.populated?(name)
    connection = ApplicationRecord.connection
    connection.select_value(
      "SELECT relispopulated FROM pg_class WHERE relname = #{connection.quote(name)}"
    )
  end

  def self.recreate!
    ApplicationRecord.connection.execute(drop_sql + create_sql)
  end

  def self.drop_sql
    ALIGNED_VIEWS.map { |name| "DROP MATERIALIZED VIEW IF EXISTS #{name} CASCADE;\n" }.join
  end

  # Regra da comparação alinhada, em um lugar só: o mês anterior cheio nunca é recortado;
  # os dois períodos comparáveis são recortados pelo mesmo dia. A view materializada usa o
  # corte de cada canal; o ReportScope injeta o menor corte do recorte selecionado.
  def self.revenue_by_sub_channel_sql(cutoff:, channel_predicate: "TRUE")
    <<~SQL
      WITH open_cover AS (
        SELECT channel_id, period AS current_period, max_known_day,
          (period - INTERVAL '1 month')::date AS previous_period
        FROM period_coverages
        WHERE NOT closed AND #{channel_predicate}
      ), latest_batches AS (
        SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots snapshot WHERE snapshot.import_batch_id = ib.id
          )
        GROUP BY ib.channel_id
      )
      SELECT snapshot.channel_id, snapshot.sub_channel_id, sub_channel.uuid, sub_channel.name AS sub_channel_name,
        cover.previous_period, cover.current_period, #{cutoff} AS max_known_day,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = cover.previous_period
        ), 0) AS faturamento_m1_cheio,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = cover.previous_period AND revenue.day <= #{cutoff}
        ), 0) AS faturamento_m1,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = cover.current_period AND revenue.day <= #{cutoff}
        ), 0) AS faturamento_atual,
        COUNT(DISTINCT snapshot.establishment_id) FILTER (
          WHERE establishment.primary_establishment_id IS NULL
        ) AS estabelecimentos_principais
      FROM revenue_snapshots snapshot
      JOIN latest_batches latest ON latest.import_batch_id = snapshot.import_batch_id
      JOIN open_cover cover ON cover.channel_id = snapshot.channel_id
      JOIN sub_channels sub_channel ON sub_channel.id = snapshot.sub_channel_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.channel_id = snapshot.channel_id
        AND revenue.establishment_id = snapshot.establishment_id
        AND revenue.period IN (cover.previous_period, cover.current_period)
      GROUP BY snapshot.channel_id, snapshot.sub_channel_id, sub_channel.uuid, sub_channel.name,
        cover.previous_period, cover.current_period, cover.max_known_day
    SQL
  end

  def self.create_sql
    <<~SQL
      CREATE MATERIALIZED VIEW audit_revenue_by_sub_channel AS
      #{revenue_by_sub_channel_sql(cutoff: 'cover.max_known_day')};
      CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel
        ON audit_revenue_by_sub_channel (channel_id, sub_channel_id);

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      SELECT sub_channel.channel_id, sub_channel.sub_channel_id, establishment.company_id,
        company.cnpj, sub_channel.max_known_day, sub_channel.previous_period,
        sub_channel.current_period,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = sub_channel.previous_period
        ), 0) AS faturamento_m1_cheio,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = sub_channel.previous_period
            AND revenue.day <= sub_channel.max_known_day
        ), 0) AS faturamento_m1,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = sub_channel.current_period
            AND revenue.day <= sub_channel.max_known_day
        ), 0) AS faturamento_atual,
        MAX(revenue.day) FILTER (
          WHERE revenue.period = sub_channel.current_period
            AND revenue.day <= sub_channel.max_known_day AND revenue.amount <> 0
        ) AS last_sale_day
      FROM audit_revenue_by_sub_channel sub_channel
      JOIN revenue_snapshots snapshot
        ON snapshot.channel_id = sub_channel.channel_id
        AND snapshot.sub_channel_id = sub_channel.sub_channel_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.channel_id = sub_channel.channel_id
        AND revenue.establishment_id = snapshot.establishment_id
        AND revenue.period IN (sub_channel.previous_period, sub_channel.current_period)
      WHERE snapshot.import_batch_id = (
        SELECT MAX(ib.id) FROM import_batches ib
        WHERE ib.channel_id = snapshot.channel_id
          AND ib.status = 'validated'
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots latest WHERE latest.import_batch_id = ib.id
          )
      )
      GROUP BY sub_channel.channel_id, sub_channel.sub_channel_id, establishment.company_id,
        company.cnpj, sub_channel.max_known_day, sub_channel.previous_period,
        sub_channel.current_period;
      CREATE UNIQUE INDEX index_audit_revenue_by_company
        ON audit_revenue_by_company (channel_id, sub_channel_id, company_id);

      CREATE MATERIALIZED VIEW audit_stalled_companies AS
      SELECT company_view.channel_id, company_view.sub_channel_id, sub_channel.name AS sub_channel_name,
        company_view.company_id, company_view.cnpj, company_view.max_known_day,
        company_view.last_sale_day,
        company_view.max_known_day - COALESCE(company_view.last_sale_day, 0)
          AS dias_sem_venda,
        company_view.faturamento_m1_cheio, company_view.faturamento_m1,
        company_view.faturamento_atual
      FROM audit_revenue_by_company company_view
      JOIN sub_channels sub_channel ON sub_channel.id = company_view.sub_channel_id
      WHERE company_view.max_known_day - COALESCE(company_view.last_sale_day, 0)
        >= #{STALLED_THRESHOLD};
      CREATE UNIQUE INDEX index_audit_stalled_companies
        ON audit_stalled_companies (channel_id, sub_channel_id, company_id);
    SQL
  end
end
