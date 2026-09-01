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

  def revenue_by_establishment(sub_channel_id:, period: nil, from_day: nil, to_day: nil, **filters)
    window = establishment_window(period:, from_day:, to_day:)
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

    RevenueSnapshot.where(import_batch_id:, sub_channel_id:).where.not(contract_status: [ nil, "" ])
      .distinct.order(:contract_status).pluck(:contract_status)
  end

  def available_periods
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
      SELECT period, max_known_day, closed
      FROM period_coverages
      WHERE #{CHANNEL_PREDICATE}
      ORDER BY period DESC
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def establishment_window(period: nil, from_day: nil, to_day: nil)
    PeriodWindow.from_coverages(available_periods, period:, from_day:, to_day:)
  end

  def stalled_companies
    query(:stalled_companies, "cnpj")
  end

  def three_month_earnings(periods:)
    ThreeMonthEarningsQuery.new(periods:, channel_id: @channel_id).by_sub_channel
  end

  def three_month_establishments(periods:, sub_channel_id:)
    ThreeMonthEarningsQuery.new(periods:, channel_id: @channel_id).by_establishment(sub_channel_id:)
  end

  def weekly_revenue
    query(:weekly_revenue, "period, week")
  end

  # Menor corte entre os canais do recorte: comparar períodos de durações diferentes
  # entre canais distorceria a variação.
  def cutoff_day
    coverages.map { |row| row["max_known_day"].to_i }.min
  end

  def mixed_cutoffs?
    coverages.map { |row| row["max_known_day"].to_i }.uniq.size > 1
  end

  def totals
    cutoff = cutoff_day
    return empty_totals unless cutoff

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id, cutoff: cutoff.to_i } ])
      WITH open_cover AS (
        SELECT channel_id, period, max_known_day,
          (period - INTERVAL '1 month')::date AS previous_period
        FROM period_coverages
        WHERE NOT closed AND #{CHANNEL_PREDICATE}
      )
      SELECT COALESCE(SUM(dr.amount) FILTER (WHERE dr.period = oc.previous_period), 0)
               AS previous_full_revenue,
             COALESCE(SUM(dr.amount) FILTER (
               WHERE dr.period = oc.previous_period AND dr.day <= :cutoff), 0)
               AS previous_revenue,
             COALESCE(SUM(dr.amount) FILTER (
               WHERE dr.period = oc.period AND dr.day <= :cutoff), 0)
               AS current_revenue
      FROM daily_revenues_consolidated dr
      JOIN open_cover oc ON oc.channel_id = dr.channel_id
      WHERE dr.period IN (oc.previous_period, oc.period)
    SQL
    row = ApplicationRecord.connection.exec_query(sql).first || {}
    {
      previous_full_revenue: row["previous_full_revenue"].to_d,
      previous_revenue: row["previous_revenue"].to_d,
      current_revenue: row["current_revenue"].to_d
    }
  end

  private

  def empty_totals
    { previous_full_revenue: 0.to_d, previous_revenue: 0.to_d, current_revenue: 0.to_d }
  end

  def aligned_revenue_by_sub_channel
    cutoff = cutoff_day
    return [] unless cutoff

    sql = ApplicationRecord.sanitize_sql_array([
      "#{AuditViews.revenue_by_sub_channel_sql(cutoff: ':cutoff', channel_predicate: CHANNEL_PREDICATE)} " \
        "ORDER BY sub_channel.name",
      { channel_id: @channel_id, cutoff: cutoff.to_i }
    ])
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def coverages
    @coverages ||= begin
      sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
        SELECT channel_id, max_known_day FROM period_coverages
        WHERE NOT closed AND #{CHANNEL_PREDICATE}
      SQL
      ApplicationRecord.connection.exec_query(sql).to_a
    end
  end

  def query(name, order_by = nil)
    table = VIEWS.fetch(name)
    # Banco recém-criado carrega as views WITH NO DATA e consultá-las levanta erro;
    # até o primeiro import o relatório é legitimamente vazio.
    return [] unless AuditViews.populated?(table)

    sql = +"SELECT * FROM #{table}"
    sql << " WHERE channel_id = #{ApplicationRecord.connection.quote(@channel_id)}" if @channel_id
    sql << " ORDER BY #{order_by}" if order_by
    ApplicationRecord.connection.exec_query(sql).to_a
  end
end
