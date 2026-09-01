class ReportsController < ApplicationController
  before_action :load_scope

  def index
    @reports = @scope.revenue_by_sub_channel
    @totals = @scope.totals
    respond_to do |format|
      format.html
      format.csv do
        send_data ReportsExporter.new(@reports, cutoff_day: @cutoff_day, totals: @totals).to_csv,
          filename: export_filename("csv"), type: "text/csv"
      end
      format.xlsx do
        send_data ReportsExporter.new(@reports, cutoff_day: @cutoff_day, totals: @totals).to_xlsx,
          filename: export_filename("xlsx"),
          type: Mime[:xlsx]
      end
    end
  end

  def stalled
    @reports = @scope.stalled_companies
  end

  def weekly
    @reports = @scope.weekly_revenue
  end

  # Série mensal do ganho recorrente: todas as competências disponíveis, sem seletor —
  # a tela cresce um mês a cada ciclo de planilhas.
  def recurring
    @reports = @scope.recurring_earnings
  end

  # Página 3M: janela de três meses de calendário à escolha do usuário, limitada aos
  # meses que os volumes mensais da planilha realmente cobrem.
  def three_months
    @available_periods = ThreeMonthEarningsQuery.available_periods(channel_id: @selected_channel&.id)
    @window = three_month_window
    @reports = @window ? @scope.three_month_earnings(periods: @window) : []
  end

  def three_months_sub_channel
    @sub_channel = SubChannel.find_param!(params[:id])
    if @selected_channel && @sub_channel.channel_id != @selected_channel.id
      raise ActiveRecord::RecordNotFound
    end

    @scope = ReportScope.new(channel_id: @sub_channel.channel_id)
    @available_periods = ThreeMonthEarningsQuery.available_periods(channel_id: @sub_channel.channel_id)
    @window = three_month_window
    @reports = @window ? @scope.three_month_establishments(periods: @window, sub_channel_id: @sub_channel.id) : []
  end

  def sub_channel
    @sub_channel = SubChannel.find_param!(params[:id])
    if @selected_channel && @sub_channel.channel_id != @selected_channel.id
      raise ActiveRecord::RecordNotFound
    end

    @scope = ReportScope.new(channel_id: @sub_channel.channel_id)
    @cutoff_day = @scope.cutoff_day
    @selected_variation = params[:variation].to_s.presence_in(EstablishmentListingQuery::VARIATION_CLAUSES.keys)
    @selected_statuses = Array(params[:status]).map(&:to_s).compact_blank.uniq
    @selected_date_kinds = Array(params[:date_kind]).map(&:to_s) & EstablishmentListingQuery::DATE_KINDS.keys
    @from_date = parse_filter_date(params[:from_date])
    @to_date = parse_filter_date(params[:to_date])
    @query = params[:q].to_s.strip
    @window = @scope.establishment_window(
      period: params[:period], from_day: params[:from_day], to_day: params[:to_day]
    )
    @from_day = @window&.from_day
    @to_day = @window&.to_day
    @period = @window&.current_period
    @status_options = (
      @scope.contract_statuses(sub_channel_id: @sub_channel.id) |
        EstablishmentsHelper::CONTRACT_STATUSES
    ).sort
    @listing = @scope.revenue_by_establishment(
      sub_channel_id: @sub_channel.id,
      variation: @selected_variation,
      statuses: @selected_statuses,
      period: params[:period],
      from_day: params[:from_day],
      to_day: params[:to_day],
      date_kinds: @selected_date_kinds,
      from_date: @from_date,
      to_date: @to_date,
      query: @query,
      page: params[:page],
      per_page: params[:per_page]
    )
    @reports = @listing.rows
    @totals = @listing.totals
    @page = @listing.page
    @per_page = @listing.per_page
    @total_count = @listing.total_count
    @total_pages = @listing.total_pages
  end

  private

  def load_scope
    @channels = Channel.order(:name)
    @selected_channel = Channel.find_param!(params[:channel_id]) if params[:channel_id].present?
    @scope = ReportScope.new(channel_id: @selected_channel&.id)
    @cutoff_day = @scope.cutoff_day
  end

  def export_filename(extension)
    "auditoria-faturamento-dia-#{@cutoff_day || 'sem-corte'}.#{extension}"
  end

  def parse_filter_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error, ArgumentError, TypeError
    nil
  end

  # O mês escolhido é o M0 — o mês de credenciamento —, e a janela avança a partir dele.
  # Meses ainda sem volume importado aparecem na tela como "sem dado", não somem.
  def three_month_window
    return nil if @available_periods.empty?

    start = parse_start_period || default_start_period
    [ start, start + 1.month, start + 2.months ]
  end

  # Sem escolha explícita, abre no M0 mais recente cuja janela ainda cabe nos meses
  # importados: abrir no último mês mostraria duas colunas vazias por padrão.
  def default_start_period
    complete = @available_periods.find do |period|
      [ period + 1.month, period + 2.months ].all? { |month| @available_periods.include?(month) }
    end
    complete || @available_periods.first
  end

  def parse_start_period
    return if params[:start_period].blank?

    parsed = Date.strptime(params[:start_period].to_s, "%Y-%m").beginning_of_month
    parsed if @available_periods.include?(parsed)
  rescue Date::Error, ArgumentError, TypeError
    nil
  end

  def sub_channel_listing_params(overrides = {})
    {
      channel_id: @selected_channel&.uuid,
      variation: @selected_variation,
      status: @selected_statuses,
      date_kind: @selected_date_kinds,
      from_date: @from_date,
      to_date: @to_date,
      q: @query,
      period: @period,
      from_day: @from_day,
      to_day: @to_day,
      per_page: @per_page,
      page: @page
    }.merge(overrides).compact_blank
  end
  helper_method :sub_channel_listing_params
end
