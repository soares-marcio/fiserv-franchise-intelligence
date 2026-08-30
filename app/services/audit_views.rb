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
    # REFRESH ... CONCURRENTLY não roda dentro de transação (Postgres recusa); nos testes,
    # que rodam em transação, caímos no refresh bloqueante.
    concurrently = connection.transaction_open? ? "" : "CONCURRENTLY "
    NAMES.each { |name| connection.execute("REFRESH MATERIALIZED VIEW #{concurrently}#{name}") }
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
        SELECT channel_id, competencia AS competencia_atual, max_dia_conhecido,
          (competencia - INTERVAL '1 month')::date AS competencia_m1
        FROM competencia_coverages
        WHERE NOT fechado AND #{channel_predicate}
      ), latest_batches AS (
        SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots snapshot WHERE snapshot.import_batch_id = ib.id
          )
        GROUP BY ib.channel_id
      )
      SELECT snapshot.channel_id, snapshot.sub_channel_id, sub_channel.uuid, sub_channel.sub_canal,
        cover.competencia_m1, cover.competencia_atual, #{cutoff} AS max_dia_conhecido,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = cover.competencia_m1
        ), 0) AS faturamento_m1_cheio,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = cover.competencia_m1 AND revenue.day <= #{cutoff}
        ), 0) AS faturamento_m1,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = cover.competencia_atual AND revenue.day <= #{cutoff}
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
        AND revenue.competencia IN (cover.competencia_m1, cover.competencia_atual)
      GROUP BY snapshot.channel_id, snapshot.sub_channel_id, sub_channel.uuid, sub_channel.sub_canal,
        cover.competencia_m1, cover.competencia_atual, cover.max_dia_conhecido
    SQL
  end

  def self.create_sql
    <<~SQL
      CREATE MATERIALIZED VIEW audit_revenue_by_sub_channel AS
      #{revenue_by_sub_channel_sql(cutoff: 'cover.max_dia_conhecido')};
      CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel
        ON audit_revenue_by_sub_channel (channel_id, sub_channel_id);

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      SELECT sub_channel.channel_id, sub_channel.sub_channel_id, establishment.company_id,
        company.cnpj, sub_channel.max_dia_conhecido, sub_channel.competencia_m1,
        sub_channel.competencia_atual,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = sub_channel.competencia_m1
        ), 0) AS faturamento_m1_cheio,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = sub_channel.competencia_m1
            AND revenue.day <= sub_channel.max_dia_conhecido
        ), 0) AS faturamento_m1,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = sub_channel.competencia_atual
            AND revenue.day <= sub_channel.max_dia_conhecido
        ), 0) AS faturamento_atual,
        MAX(revenue.day) FILTER (
          WHERE revenue.competencia = sub_channel.competencia_atual
            AND revenue.day <= sub_channel.max_dia_conhecido AND revenue.amount <> 0
        ) AS ultimo_dia_com_venda
      FROM audit_revenue_by_sub_channel sub_channel
      JOIN revenue_snapshots snapshot
        ON snapshot.channel_id = sub_channel.channel_id
        AND snapshot.sub_channel_id = sub_channel.sub_channel_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.channel_id = sub_channel.channel_id
        AND revenue.establishment_id = snapshot.establishment_id
        AND revenue.competencia IN (sub_channel.competencia_m1, sub_channel.competencia_atual)
      WHERE snapshot.import_batch_id = (
        SELECT MAX(ib.id) FROM import_batches ib
        WHERE ib.channel_id = snapshot.channel_id
          AND ib.status = 'validated'
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots latest WHERE latest.import_batch_id = ib.id
          )
      )
      GROUP BY sub_channel.channel_id, sub_channel.sub_channel_id, establishment.company_id,
        company.cnpj, sub_channel.max_dia_conhecido, sub_channel.competencia_m1,
        sub_channel.competencia_atual;
      CREATE UNIQUE INDEX index_audit_revenue_by_company
        ON audit_revenue_by_company (channel_id, sub_channel_id, company_id);

      CREATE MATERIALIZED VIEW audit_stalled_companies AS
      SELECT company_view.channel_id, company_view.sub_channel_id, sub_channel.sub_canal,
        company_view.company_id, company_view.cnpj, company_view.max_dia_conhecido,
        company_view.ultimo_dia_com_venda AS last_sale_day,
        company_view.max_dia_conhecido - COALESCE(company_view.ultimo_dia_com_venda, 0)
          AS dias_sem_venda,
        company_view.faturamento_m1_cheio, company_view.faturamento_m1,
        company_view.faturamento_atual
      FROM audit_revenue_by_company company_view
      JOIN sub_channels sub_channel ON sub_channel.id = company_view.sub_channel_id
      WHERE company_view.max_dia_conhecido - COALESCE(company_view.ultimo_dia_com_venda, 0)
        >= #{STALLED_THRESHOLD};
      CREATE UNIQUE INDEX index_audit_stalled_companies
        ON audit_stalled_companies (channel_id, sub_channel_id, company_id);
    SQL
  end
end
