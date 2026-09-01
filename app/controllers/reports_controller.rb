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
    @summary = @window ? @scope.three_month_earnings(periods: @window)
      .find { |row| row[:sub_channel_id] == @sub_channel.id } : nil
  end

  def sub_channel
    @sub_channel = SubChannel.find_param!(params[:id])
    if @selected_channel && @sub_channel.channel_id != @selected_channel.id
      raise ActiveRecord::RecordNotFound
    end

    @scope = ReportScope.new(channel_id: @sub_channel.channel_id)
    @cutoff_day = @scope.cutoff_day
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

  # O mês escolhido fecha a janela: ele e os dois anteriores. Meses fora da cobertura de
  # volumes aparecem na tela como "sem dado", não somem.
  def three_month_window
    return nil if @available_periods.empty?

    start = parse_start_period || @available_periods.first
    [ start - 2.months, start - 1.month, start ]
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
