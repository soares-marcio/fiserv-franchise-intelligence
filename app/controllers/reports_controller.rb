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
      competencia: params[:competencia], from_day: params[:from_day], to_day: params[:to_day]
    )
    @from_day = @window&.from_day
    @to_day = @window&.to_day
    @competencia = @window&.competencia_atual
    @status_options = (
      @scope.contract_statuses(sub_channel_id: @sub_channel.id) |
        EstablishmentsHelper::CONTRACT_STATUSES
    ).sort
    @listing = @scope.revenue_by_establishment(
      sub_channel_id: @sub_channel.id,
      statuses: @selected_statuses,
      competencia: params[:competencia],
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
    @channels = Channel.order(:canal)
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

  def sub_channel_listing_params(overrides = {})
    {
      channel_id: @selected_channel&.uuid,
      status: @selected_statuses,
      date_kind: @selected_date_kinds,
      from_date: @from_date,
      to_date: @to_date,
      q: @query,
      competencia: @competencia,
      from_day: @from_day,
      to_day: @to_day,
      per_page: @per_page,
      page: @page
    }.merge(overrides).compact_blank
  end
  helper_method :sub_channel_listing_params
end
