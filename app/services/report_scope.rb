class ReportScope
  VIEWS = {
    revenue_by_sub_channel: "audit_revenue_by_sub_channel",
    revenue_by_company: "audit_revenue_by_company",
    stalled_companies: "audit_stalled_companies",
    weekly_revenue: "audit_weekly_revenue",
    pending_actions: "audit_pending_actions",
    company_ec_divergence: "audit_company_ec_divergence"
  }.freeze

  def initialize(channel_id: nil)
    @channel_id = channel_id
  end

  def revenue_by_sub_channel
    @revenue_by_sub_channel ||= aligned_revenue_by_sub_channel
  end

  def revenue_by_company
    query(:revenue_by_company, "cnpj")
  end

  def stalled_companies
    query(:stalled_companies, "cnpj")
  end

  def weekly_revenue
    query(:weekly_revenue, "competencia, semana")
  end

  def pending_actions
    query(:pending_actions, "texto")
  end

  def company_ec_divergence
    query(:company_ec_divergence)
  end

  def cutoff_day
    coverages.map { |row| row["max_dia_conhecido"].to_i }.min
  end

  def mixed_cutoffs?
    coverages.map { |row| row["max_dia_conhecido"].to_i }.uniq.size > 1
  end

  def totals
    comparison_totals
  end

  def aligned_totals
    comparison_totals
  end

  def comparison_totals
    cutoff = cutoff_day
    return { faturamento_m1: 0.to_d, faturamento_atual: 0.to_d } unless cutoff

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id, cutoff: cutoff.to_i } ])
      WITH open_cover AS (
        SELECT channel_id, competencia, max_dia_conhecido,
          (competencia - INTERVAL '1 month')::date AS competencia_m1
        FROM competencia_coverages
        WHERE NOT fechado AND (:channel_id IS NULL OR channel_id = :channel_id)
      )
      SELECT COALESCE(SUM(CASE WHEN dr.competencia = oc.competencia_m1 THEN dr.amount END), 0)
               AS faturamento_m1_cheio,
             COALESCE(SUM(CASE WHEN dr.competencia = oc.competencia_m1 AND dr.day <= :cutoff
               THEN dr.amount END), 0)
               AS faturamento_m1,
             COALESCE(SUM(CASE WHEN dr.competencia = oc.competencia AND dr.day <= :cutoff
               THEN dr.amount END), 0)
               AS faturamento_atual
      FROM daily_revenues_consolidated dr
      JOIN open_cover oc ON oc.channel_id = dr.channel_id
      WHERE dr.competencia IN (oc.competencia_m1, oc.competencia)
    SQL
    row = ApplicationRecord.connection.exec_query(sql).first || {}
    {
      faturamento_m1_cheio: row["faturamento_m1_cheio"].to_d,
      faturamento_m1: row["faturamento_m1"].to_d,
      faturamento_atual: row["faturamento_atual"].to_d
    }
  end

  private

  def aligned_revenue_by_sub_channel
    cutoff = cutoff_day
    return [] unless cutoff

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id, cutoff: cutoff.to_i } ])
      WITH open_cover AS (
        SELECT channel_id, competencia AS competencia_atual,
          (competencia - INTERVAL '1 month')::date AS competencia_m1
        FROM competencia_coverages
        WHERE NOT fechado AND (:channel_id IS NULL OR channel_id = :channel_id)
      ), latest_batches AS (
        SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots snapshot WHERE snapshot.import_batch_id = ib.id
          )
        GROUP BY ib.channel_id
      )
      SELECT snapshot.channel_id, snapshot.sub_channel_id, sub_channel.sub_canal,
        cover.competencia_m1, cover.competencia_atual, :cutoff AS max_dia_conhecido,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = cover.competencia_m1
        ), 0) AS faturamento_m1_cheio,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = cover.competencia_m1 AND revenue.day <= :cutoff
        ), 0) AS faturamento_m1,
        COALESCE(SUM(revenue.amount) FILTER (
          WHERE revenue.competencia = cover.competencia_atual AND revenue.day <= :cutoff
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
      GROUP BY snapshot.channel_id, snapshot.sub_channel_id, sub_channel.sub_canal,
        cover.competencia_m1, cover.competencia_atual
      ORDER BY sub_channel.sub_canal
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def coverages
    @coverages ||= begin
      sql = + "SELECT channel_id, max_dia_conhecido FROM competencia_coverages WHERE NOT fechado"
      sql << channel_predicate
      ApplicationRecord.connection.exec_query(sql).to_a
    end
  end

  def channel_predicate
    return "" unless @channel_id

    " AND channel_id = #{ApplicationRecord.connection.quote(@channel_id)}"
  end

  def query(name, order_by = nil)
    table = VIEWS.fetch(name)
    sql = + "SELECT * FROM #{table}"
    sql << " WHERE channel_id = #{ApplicationRecord.connection.quote(@channel_id)}" if @channel_id
    sql << " ORDER BY #{order_by}" if order_by
    ApplicationRecord.connection.exec_query(sql).to_a
  end
end
