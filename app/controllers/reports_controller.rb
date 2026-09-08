class ReportsController < ApplicationController
  before_action :load_scope

  def index
    @order = ListingSort.new(columns: ReportScope::SUB_CHANNEL_SORT_COLUMNS,
      default: "previous_full_revenue", column: params[:sort], direction: params[:direction])
    @reports = @order.sort_rows(@scope.revenue_by_sub_channel)
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
    @order = ListingSort.new(
      columns: { "revenue" => "Faturamento", "establishments" => "ECs com movimento" },
      default: "revenue", column: params[:sort], direction: params[:direction]
    )
    @reports = @order.sort_rows(@scope.weekly_revenue)
  end

  # Série mensal do ganho recorrente: todas as competências disponíveis, sem seletor —
  # a tela cresce um mês a cada ciclo de planilhas.
  def recurring
    @order = ListingSort.new(columns: ReportScope::RECURRING_SORT_COLUMNS, default: "earnings",
      column: params[:sort], direction: params[:direction])
    @reports = @order.sort_rows(@scope.recurring_earnings) { |row| recurring_sort_value(row) }
  end

  # Página 3M: janela de três meses de calendário à escolha do usuário, limitada aos
  # meses que os volumes mensais da planilha realmente cobrem.
  def three_months
    @available_periods = ThreeMonthEarningsQuery.available_periods(channel_id: @selected_channel&.id)
    @window = three_month_window
    @reports = @window ? @scope.three_month_earnings(periods: @window) : []
    @order = three_month_order
    @reports = @order.sort_rows(@reports) { |row| three_month_value(row) }
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
    @selected_variation = params[:variation].to_s.presence_in(EstablishmentListingQuery::VARIATION_CLAUSES.keys)
    @selected_statuses = Array(params[:status]).map(&:to_s).compact_blank.uniq
    @selected_date_kinds = Array(params[:date_kind]).map(&:to_s) & EstablishmentListingQuery::DATE_KINDS.keys
    @from_date = parse_filter_date(params[:from_date])
    @to_date = parse_filter_date(params[:to_date])
    @query = params[:q].to_s.strip
    # A tela precisa saber a ordem efetiva, não só a pedida: sem isso o cabeçalho não marca
    # a coluna que está ordenando quando o usuário não escolheu nenhuma.
    @order = EstablishmentListingQuery.listing_sort(column: params[:sort], direction: params[:direction])
    @sort = @order.column
    @direction = @order.direction
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
    # A página só existe na tela; a exportação leva o recorte inteiro e não precisa dela.
    respond_to do |format|
      format.html { load_listing }
      format.csv { send_data listing_exporter.to_csv, filename: listing_filename("csv"), type: "text/csv" }
      format.xlsx { send_data listing_exporter.to_xlsx, filename: listing_filename("xlsx"), type: Mime[:xlsx] }
    end
  end

  # Conteúdo do modal de lançamentos diários: chega por Turbo Frame, sem layout, com a mesma
  # janela e faixa de dias da tela que o abriu.
  def sub_channel_daily
    @sub_channel = SubChannel.find_param!(params[:id])
    @scope = ReportScope.new(channel_id: @sub_channel.channel_id)
    @establishment = Establishment.where(channel_id: @sub_channel.channel_id)
                                  .find_param!(params[:establishment_id])
    @window = @scope.establishment_window(
      period: params[:period], from_day: params[:from_day], to_day: params[:to_day]
    )
    @rows = @scope.establishment_daily_revenues(establishment_id: @establishment.id, window: @window)

    render partial: "reports/daily_revenues", layout: false
  end

  private

  # O card do recorrente ordena por valores da janela inteira. O nome sai como string, então
  # sort_rows recebe o texto e a comparação é alfabética; os demais são dinheiro.
  def recurring_sort_value(row)
    case @order.column
    when "name" then row[:name]
    when "last_month"
      fechado = row[:months].reject { |month| month[:partial] }.max_by { |month| month[:period] }
      fechado ? fechado[:recurring] + fechado[:accelerator] - fechado[:reducer] : 0
    else row[:recurring_total] + row[:adjustment_total]
    end
  end

  # A linha da tela 3M é o subcanal, e cada mês da janela é uma coluna: ordenar por M0, M1
  # ou M2 é ordenar por aquele mês; "ECs no M0" e "prêmio" são valores da linha inteira.
  def three_month_order
    columns = { "accredited" => "ECs no M0", "prize" => "Prêmio da safra" }
    Array(@window).each_with_index { |period, index| columns["m#{index}"] = "M#{index}" }
    ListingSort.new(columns:, default: "prize", column: params[:sort], direction: params[:direction])
  end

  def three_month_value(row)
    case @order.column
    when "accredited" then row.dig(:prize, :accredited).to_d
    when "prize" then row.dig(:prize, :addon_without_auto).to_d + row.dig(:prize, :digitalization).to_d
    else row[:months][@order.column.delete_prefix("m").to_i]&.fetch(:total).to_d
    end
  end

  # A janela do 3M vem do calendário (from_date/to_date). Os parâmetros antigos continuam
  # aceitos para não quebrar link salvo: o que muda é a origem, não a regra.
  def three_month_window
    ThreeMonthEarningsQuery.window(@available_periods,
      start_period: params[:from_date].presence || params[:start_period],
      end_period: params[:to_date].presence || params[:end_period])
  end

  def load_listing
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
      sort: @sort,
      direction: @direction,
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

  def load_scope
    @channels = Channel.order(:name)
    @selected_channel = Channel.find_param!(params[:channel_id]) if params[:channel_id].present?
    @scope = ReportScope.new(channel_id: @selected_channel&.id)
    @cutoff_day = @scope.cutoff_day
  end

  # A exportação repete o recorte da tela e larga a paginação: o arquivo é do filtro, não
  # da página que o usuário estava vendo.
  def listing_exporter
    rows = @scope.establishment_rows(
      sub_channel_id: @sub_channel.id, variation: @selected_variation,
      statuses: @selected_statuses, period: params[:period],
      from_day: params[:from_day], to_day: params[:to_day],
      date_kinds: @selected_date_kinds, from_date: @from_date, to_date: @to_date, query: @query,
      sort: @sort, direction: @direction
    )
    EstablishmentListingExporter.new(rows, sub_channel_name: @sub_channel.name, window: @window)
  end

  def listing_filename(extension)
    "#{@sub_channel.name.parameterize}-estabelecimentos.#{extension}"
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
      variation: @selected_variation,
      status: @selected_statuses,
      date_kind: @selected_date_kinds,
      from_date: @from_date,
      to_date: @to_date,
      q: @query,
      # A ordem padrão não vai na URL: ela é o estado natural da tela.
      **(@order&.params || {}),
      period: @period,
      from_day: @from_day,
      to_day: @to_day,
      per_page: @per_page,
      page: @page
    }.merge(overrides).compact_blank
  end
  helper_method :sub_channel_listing_params

  # Os links de ordenação da tela 3M levam o canal e a janela do calendário junto, senão
  # ordenar recomeçaria a apuração noutra janela.
  def three_month_order_params(overrides = {})
    {
      channel_id: @selected_channel&.uuid,
      from_date: @window&.first,
      to_date: @window&.last
    }.merge(overrides).compact_blank
  end
  helper_method :three_month_order_params
end
