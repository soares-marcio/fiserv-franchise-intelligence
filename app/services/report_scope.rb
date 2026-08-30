class ReportScope
  VIEWS = {
    stalled_companies: "audit_stalled_companies",
    weekly_revenue: "audit_weekly_revenue"
  }.freeze
  CHANNEL_PREDICATE = "(:channel_id IS NULL OR channel_id = :channel_id)".freeze

  def initialize(channel_id: nil)
    @channel_id = channel_id
  end

  def revenue_by_sub_channel
    @revenue_by_sub_channel ||= aligned_revenue_by_sub_channel
  end

  def revenue_by_establishment(sub_channel_id:, competencia: nil, from_day: nil, to_day: nil, **filters)
    window = establishment_window(competencia:, from_day:, to_day:)
    return EstablishmentListingQuery.empty_page unless window

    EstablishmentListingQuery.new(
      channel_id: @channel_id, sub_channel_id:, window:, **filters
    ).call
  end

  def contract_statuses(sub_channel_id:)
    sub_channel = SubChannel.find(sub_channel_id)
    channel_id = @channel_id || sub_channel.channel_id
    import_batch_id = ImportBatch.where(channel_id:, status: "validated")
      .joins(:revenue_snapshots).maximum(:id)
    return [] unless import_batch_id

    RevenueSnapshot.where(import_batch_id:, sub_channel_id:).where.not(status_contrato: [ nil, "" ])
      .distinct.order(:status_contrato).pluck(:status_contrato)
  end

  def available_competencias
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
      SELECT competencia, max_dia_conhecido, fechado
      FROM competencia_coverages
      WHERE #{CHANNEL_PREDICATE}
      ORDER BY competencia DESC
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def establishment_window(competencia: nil, from_day: nil, to_day: nil)
    CompetenciaWindow.from_coverages(available_competencias, competencia:, from_day:, to_day:)
  end

  def stalled_companies
    query(:stalled_companies, "cnpj")
  end

  def weekly_revenue
    query(:weekly_revenue, "competencia, semana")
  end

  # Menor corte entre os canais do recorte: comparar períodos de durações diferentes
  # entre canais distorceria a variação.
  def cutoff_day
    coverages.map { |row| row["max_dia_conhecido"].to_i }.min
  end

  def mixed_cutoffs?
    coverages.map { |row| row["max_dia_conhecido"].to_i }.uniq.size > 1
  end

  def totals
    cutoff = cutoff_day
    return empty_totals unless cutoff

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id, cutoff: cutoff.to_i } ])
      WITH open_cover AS (
        SELECT channel_id, competencia, max_dia_conhecido,
          (competencia - INTERVAL '1 month')::date AS competencia_m1
        FROM competencia_coverages
        WHERE NOT fechado AND #{CHANNEL_PREDICATE}
      )
      SELECT COALESCE(SUM(dr.amount) FILTER (WHERE dr.competencia = oc.competencia_m1), 0)
               AS faturamento_m1_cheio,
             COALESCE(SUM(dr.amount) FILTER (
               WHERE dr.competencia = oc.competencia_m1 AND dr.day <= :cutoff), 0)
               AS faturamento_m1,
             COALESCE(SUM(dr.amount) FILTER (
               WHERE dr.competencia = oc.competencia AND dr.day <= :cutoff), 0)
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

  def empty_totals
    { faturamento_m1_cheio: 0.to_d, faturamento_m1: 0.to_d, faturamento_atual: 0.to_d }
  end

  def aligned_revenue_by_sub_channel
    cutoff = cutoff_day
    return [] unless cutoff

    sql = ApplicationRecord.sanitize_sql_array([
      "#{AuditViews.revenue_by_sub_channel_sql(cutoff: ':cutoff', channel_predicate: CHANNEL_PREDICATE)} " \
        "ORDER BY sub_channel.sub_canal",
      { channel_id: @channel_id, cutoff: cutoff.to_i }
    ])
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def coverages
    @coverages ||= begin
      sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
        SELECT channel_id, max_dia_conhecido FROM competencia_coverages
        WHERE NOT fechado AND #{CHANNEL_PREDICATE}
      SQL
      ApplicationRecord.connection.exec_query(sql).to_a
    end
  end

  def query(name, order_by = nil)
    table = VIEWS.fetch(name)
    sql = +"SELECT * FROM #{table}"
    sql << " WHERE channel_id = #{ApplicationRecord.connection.quote(@channel_id)}" if @channel_id
    sql << " ORDER BY #{order_by}" if order_by
    ApplicationRecord.connection.exec_query(sql).to_a
  end
end
