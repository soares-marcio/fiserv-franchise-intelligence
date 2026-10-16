class AuditViews
  NAMES = %w[
    audit_revenue_by_sub_channel audit_revenue_by_company audit_stalled_companies
    audit_weekly_revenue audit_accreditation_earnings
  ].freeze

  # Views recriadas por este serviço; as demais nascem nas migrações que as criaram.
  ALIGNED_VIEWS = %w[
    audit_stalled_companies audit_revenue_by_company audit_revenue_by_sub_channel
  ].freeze

  # Tabelas que as views leem. O refresh roda logo depois de cada carga em massa, antes de o
  # autoanalyze acordar; sem estatísticas o planejador estimava as tabelas como vazias e as
  # duas views de faturamento levavam segundos em nested loops (2,1 s e 2,4 s contra 84 ms e
  # 108 ms com estatísticas, no import sintético de 556 ECs).
  SOURCE_TABLES = %w[
    import_batches period_coverages sub_channels companies establishments
    revenue_snapshots map_snapshots
    daily_revenues_consolidated monthly_volumes_consolidated
  ].freeze

  # Corte de cada MIC na view: o dele, nunca acima do Master — o ajuste manual de corte
  # (Operations::AdjustCutoff) mexe na cobertura do Master e continua valendo.
  SUB_CHANNEL_CUTOFF = "LEAST(cover.max_known_day, COALESCE(sub_channel_cover.max_known_day, cover.max_known_day))"

  # O nome de arquivo que o cadastro manual grava no lote (Operations::RegisterManually).
  MANUAL_SOURCE = "manual"

  # Dias sem venda a partir do qual um CNPJ entra no relatório de clientes parados.
  STALLED_THRESHOLD = 7

  def self.refresh!
    connection = ApplicationRecord.connection
    connection.execute("ANALYZE #{SOURCE_TABLES.join(', ')}")
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

  # A carteira vigente, em um lugar só: a view, a listagem, a 3M, a recorrência e os
  # indicadores leem por aqui, e uma segunda definição divergiria na primeira correção.
  #
  # O Master não chega mais num arquivo só: a Fiserv manda um arquivo com parte dos MICs e
  # outro com o resto. Por isso a foto vigente é escolhida **por MIC**, e um snapshot vale
  # quando as duas condições batem:
  #
  # (a) é do lote mais recente que traz aquele EC — o EC que trocou de MIC entre dois
  #     arquivos conta uma vez só, no MIC do arquivo mais novo;
  # (b) esse lote não é anterior ao lote vigente do MIC dele — o EC que o arquivo novo do
  #     MIC não traz sai da carteira, como saía quando o arquivo era do Master inteiro.
  #
  # O lote vigente do MIC só considera arquivo: o cadastro manual de um EC não é a carteira
  # do MIC, e deixá-lo entrar na conta esconderia todos os outros ECs dele.
  #
  # Devolve o CTE `name` com o id do snapshot vigente (e a competência, com by_period). Com
  # by_period: true a mesma regra vale dentro de cada competência — a recorrência e as bases
  # mensais olham o mês que já passou, não a carteira de hoje.
  def self.current_snapshots_sql(table: "revenue_snapshots", channel_predicate: nil,
    by_period: false, name: "current_snapshots")
    conditions = [ "ib.status = 'validated'", channel_predicate ].compact.join(" AND ")
    period = ", ib.current_period" if by_period
    <<~SQL
      #{name} AS (
        SELECT candidate.id#{", candidate.current_period" if by_period}
        FROM (
          SELECT snapshot.id, snapshot.import_batch_id, snapshot.channel_id,
            snapshot.sub_channel_id#{period},
            MAX(snapshot.import_batch_id) OVER (
              PARTITION BY snapshot.establishment_id#{period}
            ) AS establishment_batch_id
          FROM #{table} snapshot
          JOIN import_batches ib ON ib.id = snapshot.import_batch_id
          WHERE #{conditions}
        ) candidate
        LEFT JOIN (
          SELECT snapshot.channel_id, snapshot.sub_channel_id#{period},
            MAX(snapshot.import_batch_id) AS import_batch_id
          FROM #{table} snapshot
          JOIN import_batches ib ON ib.id = snapshot.import_batch_id
          WHERE #{conditions} AND ib.source_filename <> '#{MANUAL_SOURCE}'
          GROUP BY snapshot.channel_id, snapshot.sub_channel_id#{period}
        ) sub_channel_batch
          ON sub_channel_batch.channel_id = candidate.channel_id
          AND sub_channel_batch.sub_channel_id = candidate.sub_channel_id
          #{"AND sub_channel_batch.current_period = candidate.current_period" if by_period}
        WHERE candidate.import_batch_id = candidate.establishment_batch_id
          AND (sub_channel_batch.import_batch_id IS NULL
            OR candidate.import_batch_id >= sub_channel_batch.import_batch_id)
      )
    SQL
  end


  # Os ids dos snapshots vigentes de um Master — para quem lê a carteira de um Master só. O
  # lote em revisão sai da conta (except_batch_id): a revisão compara com o que vale hoje.
  def self.current_snapshot_ids(table:, channel_id:, except_batch_id: nil)
    cte = current_snapshots_sql(table:, channel_predicate: "ib.channel_id = :channel_id AND ib.id <> :except_batch_id")
    sql = ApplicationRecord.sanitize_sql_array([
      "WITH #{cte.strip} SELECT id FROM current_snapshots",
      { channel_id:, except_batch_id: except_batch_id || 0 }
    ])
    ApplicationRecord.connection.exec_query(sql).rows.flatten
  end

  # O corte de cada MIC na competência: o maior dia de corte entre os lotes validados que o
  # trouxeram. Com o Master em mais de um arquivo, cada arquivo tem o próprio corte, e o MIC
  # do arquivo que parou no dia 10 comparado até o dia 13 do outro pareceria queda. Só os MICs
  # com carteira vigente entram — um MIC esvaziado não puxa o corte de ninguém. Precisa do CTE
  # current_snapshots no mesmo WITH.
  def self.sub_channel_cover_sql
    <<~SQL
      sub_channel_cover AS (
        SELECT snapshot.channel_id, snapshot.sub_channel_id, ib.current_period AS period,
          MAX(ib.current_month_cutoff_day) AS max_known_day
        FROM revenue_snapshots snapshot
        JOIN import_batches ib ON ib.id = snapshot.import_batch_id
        WHERE ib.status = 'validated'
          AND (snapshot.channel_id, snapshot.sub_channel_id) IN (
            SELECT vigente.channel_id, vigente.sub_channel_id
            FROM revenue_snapshots vigente
            JOIN current_snapshots current ON current.id = vigente.id
          )
        GROUP BY snapshot.channel_id, snapshot.sub_channel_id, ib.current_period
      )
    SQL
  end

  # Regra da comparação alinhada, em um lugar só: o mês anterior cheio nunca é recortado e os
  # dois períodos comparáveis levam o mesmo recorte de dias. A view materializada recorta pelo
  # corte de cada canal; o ReportScope injeta o menor corte do recorte; a listagem usa a faixa
  # escolhida na tela. Só o recorte muda — a regra é a mesma nos três.
  def self.aligned_aggregates_sql(table:, previous_period:, current_period:, day_filter:)
    <<~SQL.strip
      COALESCE(SUM(#{table}.amount) FILTER (
        WHERE #{table}.period = #{previous_period}
      ), 0) AS previous_full_revenue,
      COALESCE(SUM(#{table}.amount) FILTER (
        WHERE #{table}.period = #{previous_period} AND #{day_filter}
      ), 0) AS previous_revenue,
      COALESCE(SUM(#{table}.amount) FILTER (
        WHERE #{table}.period = #{current_period} AND #{day_filter}
      ), 0) AS current_revenue
    SQL
  end

  def self.revenue_by_sub_channel_sql(cutoff:, channel_predicate: "TRUE", snapshot_predicate: "TRUE")
    <<~SQL
      WITH open_cover AS (
        SELECT channel_id, period AS current_period, max_known_day,
          (period - INTERVAL '1 month')::date AS previous_period
        FROM period_coverages
        WHERE NOT closed AND #{channel_predicate}
      ), #{current_snapshots_sql.strip},
      #{sub_channel_cover_sql.strip}
      SELECT snapshot.channel_id, snapshot.sub_channel_id, sub_channel.uuid, sub_channel.name AS sub_channel_name,
        cover.previous_period, cover.current_period, #{cutoff} AS max_known_day,
        #{aligned_aggregates_sql(table: 'revenue', previous_period: 'cover.previous_period',
          current_period: 'cover.current_period', day_filter: "revenue.day <= #{cutoff}").indent(4).strip},
        COUNT(DISTINCT snapshot.establishment_id) FILTER (
          WHERE establishment.primary_establishment_id IS NULL
        ) AS primary_establishments
      FROM revenue_snapshots snapshot
      JOIN current_snapshots current ON current.id = snapshot.id
      JOIN open_cover cover ON cover.channel_id = snapshot.channel_id
      LEFT JOIN sub_channel_cover
        ON sub_channel_cover.channel_id = snapshot.channel_id
        AND sub_channel_cover.sub_channel_id = snapshot.sub_channel_id
        AND sub_channel_cover.period = cover.current_period
      JOIN sub_channels sub_channel ON sub_channel.id = snapshot.sub_channel_id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.channel_id = snapshot.channel_id
        AND revenue.establishment_id = snapshot.establishment_id
        AND revenue.period IN (cover.previous_period, cover.current_period)
      WHERE #{snapshot_predicate}
      GROUP BY snapshot.channel_id, snapshot.sub_channel_id, sub_channel.uuid, sub_channel.name,
        cover.previous_period, cover.current_period, cover.max_known_day,
        sub_channel_cover.max_known_day
    SQL
  end

  def self.create_sql
    <<~SQL
      CREATE MATERIALIZED VIEW audit_revenue_by_sub_channel AS
      #{revenue_by_sub_channel_sql(cutoff: SUB_CHANNEL_CUTOFF)};
      CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel
        ON audit_revenue_by_sub_channel (channel_id, sub_channel_id);

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      WITH #{current_snapshots_sql.strip}
      SELECT sub_channel.channel_id, sub_channel.sub_channel_id, establishment.company_id,
        company.cnpj, sub_channel.max_known_day, sub_channel.previous_period,
        sub_channel.current_period,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = sub_channel.previous_period
        ), 0) AS previous_full_revenue,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = sub_channel.previous_period
            AND revenue.day <= sub_channel.max_known_day
        ), 0) AS previous_revenue,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.period = sub_channel.current_period
            AND revenue.day <= sub_channel.max_known_day
        ), 0) AS current_revenue,
        MAX(revenue.day) FILTER (
          WHERE revenue.period = sub_channel.current_period
            AND revenue.day <= sub_channel.max_known_day AND revenue.amount <> 0
        ) AS last_sale_day
      FROM audit_revenue_by_sub_channel sub_channel
      JOIN revenue_snapshots snapshot
        ON snapshot.channel_id = sub_channel.channel_id
        AND snapshot.sub_channel_id = sub_channel.sub_channel_id
      JOIN current_snapshots current ON current.id = snapshot.id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN companies company ON company.id = establishment.company_id
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.channel_id = sub_channel.channel_id
        AND revenue.establishment_id = snapshot.establishment_id
        AND revenue.period IN (sub_channel.previous_period, sub_channel.current_period)
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
          AS days_without_sales,
        company_view.previous_full_revenue, company_view.previous_revenue,
        company_view.current_revenue
      FROM audit_revenue_by_company company_view
      JOIN sub_channels sub_channel ON sub_channel.id = company_view.sub_channel_id
      WHERE company_view.max_known_day - COALESCE(company_view.last_sale_day, 0)
        >= #{STALLED_THRESHOLD};
      CREATE UNIQUE INDEX index_audit_stalled_companies
        ON audit_stalled_companies (channel_id, sub_channel_id, company_id);
    SQL
  end
end
