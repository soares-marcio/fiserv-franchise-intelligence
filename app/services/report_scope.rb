class ReportScope
  # Colunas de valor que a tela de faturamento por subcanal deixa ordenar, com o rótulo que
  # levam no cabeçalho. A listagem vem inteira da consulta em cache: a ordem é aplicada na
  # leitura e nunca entra na chave do cache, senão cada clique viraria uma entrada nova.
  # A tela do recorrente ordena cards, não linhas: o card é o subcanal com a série dele.
  # Por isso as opções são valores da janela inteira, e não de um mês — "ordenar por débito"
  # não teria resposta única com seis competências por subcanal.
  RECURRING_SORT_COLUMNS = {
    "earnings" => "Ganho na janela",
    "last_month" => "Último mês fechado",
    "name" => "Subcanal"
  }.freeze

  SUB_CHANNEL_SORT_COLUMNS = {
    "previous_full_revenue" => "Mês anterior cheio",
    "previous_revenue" => "Mês anterior comparável",
    "current_revenue" => "Mês atual",
    "variation" => "Variação"
  }.freeze

  VIEWS = {
    stalled_companies: "audit_stalled_companies",
    weekly_revenue: "audit_weekly_revenue"
  }.freeze
  CHANNEL_PREDICATE = "(:channel_id IS NULL OR channel_id = :channel_id)".freeze

  def initialize(channel_id: nil)
    @channel_id = channel_id
  end

  # As agregações do dashboard só mudam numa consolidação ou num ajuste de corte, e os dois
  # tocam period_coverages: o carimbo dela na chave invalida o cache sozinho, como no
  # recorrente e no 3M. O corte entra porque o recorte do canal muda o dia de comparação.
  def revenue_by_sub_channel
    @revenue_by_sub_channel ||= cached("by_sub_channel") { aligned_revenue_by_sub_channel }
  end

  def revenue_by_establishment(sub_channel_id:, period: nil, from_day: nil, to_day: nil, **filters)
    listing = establishment_listing(sub_channel_id:, period:, from_day:, to_day:, **filters)
    listing ? listing.call : EstablishmentListingQuery.empty_page
  end

  # Mesmo recorte da tela sem a paginação: é o que a exportação leva.
  def establishment_rows(sub_channel_id:, period: nil, from_day: nil, to_day: nil, **filters)
    establishment_listing(sub_channel_id:, period:, from_day:, to_day:, **filters)&.all_rows || []
  end

  def contract_statuses(sub_channel_id:)
    sub_channel = SubChannel.find(sub_channel_id)
    channel_id = @channel_id || sub_channel.channel_id
    # EXISTS para em um snapshot por lote; o JOIN percorria todos os snapshots de todos os lotes.
    import_batch_id = ImportBatch.where(channel_id:, status: "validated")
      .where(RevenueSnapshot.where("revenue_snapshots.import_batch_id = import_batches.id").arel.exists)
      .maximum(:id)
    return [] unless import_batch_id

    RevenueSnapshot.where(import_batch_id:, sub_channel_id:).where.not(contract_status: [ nil, "" ])
      .distinct.order(:contract_status).pluck(:contract_status)
  end

  # Memoizado: a janela é montada para a tela e de novo para a listagem, no mesmo scope.
  def available_periods
    @available_periods ||= begin
      sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
        SELECT period, max_known_day, closed
        FROM period_coverages
        WHERE #{CHANNEL_PREDICATE}
        ORDER BY period DESC
      SQL
      ApplicationRecord.connection.exec_query(sql).to_a
    end
  end

  def establishment_window(period: nil, from_day: nil, to_day: nil)
    PeriodWindow.from_coverages(available_periods, period:, from_day:, to_day:)
  end

  # Lançamentos diários de um EC, um dia por linha e as competências lado a lado — o mesmo
  # desenho da planilha, que traz DIA 01..DIA 31. A penúltima entra porque a leitura do
  # lançamento é comparativa: dois meses mostram a mudança, três mostram a tendência. O
  # arquivo traz duas competências; a mais antiga vem das importações anteriores, e por isso
  # a coluna só aparece quando a competência tem cobertura. O mês inteiro
  # aparece, não a faixa de dias dos filtros: o modal é a leitura do lançamento, não o
  # recorte da comparação. A série vem do generate_series porque dia sem venda precisa
  # aparecer zerado, senão o modal esconde exatamente o buraco que o usuário foi ver.
  SHEET_DAYS = 31

  def establishment_daily_revenues(establishment_id:, window:)
    return [] unless window

    binds = window.to_binds.merge(establishment_id:, from_day: 1, to_day: SHEET_DAYS)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, binds ])
      SELECT dias.day,
        COALESCE(SUM(revenue.amount) FILTER (WHERE revenue.period = :current_period), 0) AS current_amount,
        COALESCE(SUM(revenue.amount) FILTER (WHERE revenue.period = :previous_period), 0) AS previous_amount,
        COALESCE(SUM(revenue.amount) FILTER (WHERE revenue.period = :penultimate_period), 0) AS penultimate_amount
      FROM generate_series(:from_day::int, :to_day::int) AS dias(day)
      LEFT JOIN daily_revenues_consolidated revenue
        ON revenue.day = dias.day
        AND revenue.establishment_id = :establishment_id
        AND revenue.period IN (:penultimate_period, :previous_period, :current_period)
      GROUP BY dias.day
      ORDER BY dias.day
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  def stalled_companies
    query(:stalled_companies, "cnpj")
  end

  def recurring_earnings
    RecurringEarningsQuery.new(channel_id: @channel_id).by_sub_channel
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

    cached("totals") { aligned_totals(cutoff) }
  end

  private

  def cached(name, &block)
    Rails.cache.fetch([ "dashboard", name, PeriodCoverage.consolidation_stamp, @channel_id, cutoff_day ], &block)
  end

  def aligned_totals(cutoff)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id, cutoff: cutoff.to_i } ])
      WITH open_cover AS (
        SELECT channel_id, period, max_known_day,
          (period - INTERVAL '1 month')::date AS previous_period
        FROM period_coverages
        WHERE NOT closed AND #{CHANNEL_PREDICATE}
      )
      SELECT #{AuditViews.aligned_aggregates_sql(
        table: "dr", previous_period: "oc.previous_period", current_period: "oc.period",
        day_filter: "dr.day <= :cutoff"
      ).indent(4).strip}
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

  def establishment_listing(sub_channel_id:, period:, from_day:, to_day:, **filters)
    window = establishment_window(period:, from_day:, to_day:)
    return unless window

    EstablishmentListingQuery.new(channel_id: @channel_id, sub_channel_id:, window:, **filters)
  end

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
