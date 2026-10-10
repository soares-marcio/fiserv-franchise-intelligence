class ReportsController < ApplicationController
  # A raiz do portal é este index; a conta da plataforma não tem carteira e cairia em 403 ao
  # entrar. Ela vai para a tela dela, antes de qualquer autorização.
  before_action -> { redirect_to platform_organizations_path if Current.user&.platform_admin? }, only: :index
  # Quem entra pela raiz sem o Faturamento vai para o primeiro item do menu que tem, em
  # vez de bater num 403 logo depois do login.
  before_action :redirect_root_to_landing, only: :index
  before_action :load_scope
  before_action -> { authorize :report, SCREEN_PERMISSIONS.fetch(action_name.to_sym) }

  # Cada ação pertence ao item do menu de onde se chega a ela. O fetch faz uma tela nova
  # sem entrada aqui falhar no primeiro teste, em vez de abrir sem autorização.
  SCREEN_PERMISSIONS = {
    index: :revenue?, sub_channel: :revenue?, sub_channel_daily: :revenue?,
    stalled: :clover?,
    weekly: :weekly?, weekly_day: :weekly?,
    three_months: :three_months?, three_months_sub_channel: :three_months?,
    recurring: :recurring?,
    indicators: :indicators?
  }.freeze

  def index
    @order = ListingSort.new(columns: ReportScope::SUB_CHANNEL_SORT_COLUMNS,
      default: "previous_full_revenue", column: params[:sort], direction: params[:direction])
    @reports = @order.sort_rows(@scope.revenue_by_sub_channel) { |row| sub_channel_sort_value(row) }
    @totals = @scope.totals
  end

  # Clover Capital: as ofertas pré-aprovadas da carteira, uma por CNPJ.
  def stalled
    @selected_sub_channel = selected_stalled_sub_channel
    offers = PreapprovedOffers.new(scope: Current.access_scope.narrow(channel: @selected_channel),
      sub_channel_id: @selected_sub_channel&.id)
    @reports = offers.call
    @sub_channels = offers.sub_channel_options
    @diverging_cnpjs = offers.diverging_cnpjs
    @diverging_name_cnpjs = offers.diverging_name_cnpjs
    respond_to do |format|
      format.html
      format.csv { authorize(:report, :export?); audit_export; send_data stalled_exporter.to_csv, **download_headers(clover_filename, "csv") }
      format.xlsx { authorize(:report, :export?); audit_export; send_data stalled_exporter.to_xlsx, **download_headers(clover_filename, "xlsx") }
    end
  end

  def weekly
    @period = calendar_period
    return if @period.nil?

    @covered_days = covered_days_for(@period)
    @calendar = RevenueCalendar.new(period: @period, covered_days: @covered_days,
      days: @scope.daily_calendar(period: @period, covered_days: @covered_days),
      weeks: @scope.weekly_calendar(period: @period, covered_days: @covered_days))
    @totals = @scope.month_totals(period: @period, up_to_day: @covered_days)
    load_previous_month_anchor
    load_calendar_neighbours
    respond_to do |format|
      format.html
      format.csv { authorize(:report, :export?); audit_export; send_data weekly_exporter.to_csv, **download_headers(weekly_filename, "csv") }
      format.xlsx { authorize(:report, :export?); audit_export; send_data weekly_exporter.to_xlsx, **download_headers(weekly_filename, "xlsx") }
    end
  end

  # A competência do calendário sai da URL, validada contra as importadas: mês sem arquivo não
  # é oferecido nem aceito. Sem escolha, abre na mais recente.
  def calendar_period
    available = @scope.available_period_dates
    requested = begin
      params[:period].presence&.to_date&.beginning_of_month
    rescue Date::Error, ArgumentError, TypeError
      nil
    end
    available.include?(requested) ? requested : available.first
  end

  # As setas andam só entre competências importadas — não existe mês vazio para onde ir. A
  # lista vem em ordem decrescente, então a anterior está adiante no array.
  def load_calendar_neighbours
    periods = @scope.available_period_dates
    position = periods.index(@period)
    @newer_period = position.positive? ? periods[position - 1] : nil
    @older_period = periods[position + 1]
  end

  def covered_days_for(period)
    [ @scope.covered_day_of(period), Time.days_in_month(period.month, period.year) ].min
  end

  # Âncora do mês anterior, com a regra de alinhamento da casa: mês escolhido fechado compara
  # com o anterior inteiro; mês escolhido parcial compara com o anterior **até o mesmo dia**.
  # Sem isso, setembro com dois dias apareceria como queda de 93%.
  def load_previous_month_anchor
    @previous_period = @period.prev_month
    return unless @scope.available_period_dates.include?(@previous_period)

    @aligned = @covered_days < Time.days_in_month(@period.month, @period.year)
    @previous_totals = @scope.month_totals(
      period: @previous_period,
      up_to_day: @aligned ? @covered_days : covered_days_for(@previous_period)
    )
  end

  # Série mensal do ganho recorrente: todas as competências disponíveis, sem seletor —
  # a tela cresce um mês a cada ciclo de planilhas.
  def recurring
    @order = ListingSort.new(columns: ReportScope::RECURRING_SORT_COLUMNS, default: "earnings",
      column: params[:sort], direction: params[:direction])
    @reports = @order.sort_rows(@scope.recurring_earnings) { |row| recurring_sort_value(row) }
    respond_to do |format|
      format.html
      format.csv { authorize(:report, :export?); audit_export; send_data recurring_exporter.to_csv, **download_headers("ganho-recorrente", "csv") }
      format.xlsx { authorize(:report, :export?); audit_export; send_data recurring_exporter.to_xlsx, **download_headers("ganho-recorrente", "xlsx") }
    end
  end

  # Indicadores do Anexo B: um card por MIC, com a leitura de cada competência.
  def indicators
    @order = ListingSort.new(columns: ReportScope::INDICATOR_SORT_COLUMNS, default: "risk",
      column: params[:sort], direction: params[:direction])
    @reports = @order.sort_rows(@scope.sub_channel_indicators) { |row| indicator_sort_value(row) }
  end

  # Página 3M: janela de três meses de calendário à escolha do usuário, limitada aos
  # meses que os volumes mensais da planilha realmente cobrem.
  def three_months
    @available_periods = ThreeMonthEarningsQuery.available_periods(scope: @scope.scope)
    @window = three_month_window
    @reports = @window ? @scope.three_month_earnings(periods: @window) : []
    @order = three_month_order
    @reports = @order.sort_rows(@reports) { |row| three_month_value(row) }
    respond_to do |format|
      format.html
      format.csv { authorize(:report, :export?); audit_export; send_data three_month_exporter.to_csv, **download_headers("ganhos-3m", "csv") }
      format.xlsx { authorize(:report, :export?); audit_export; send_data three_month_exporter.to_xlsx, **download_headers("ganhos-3m", "xlsx") }
    end
  end

  def three_months_sub_channel
    @sub_channel = policy_scope(SubChannel).find_param!(params[:id])
    if @selected_channel && @sub_channel.channel_id != @selected_channel.id
      raise ActiveRecord::RecordNotFound
    end

    @scope = ReportScope.new(scope: Current.access_scope.narrow(sub_channel: @sub_channel))
    @available_periods = ThreeMonthEarningsQuery.available_periods(scope: @scope.scope)
    @window = three_month_window
    @reports = @window ? @scope.three_month_establishments(periods: @window, sub_channel_id: @sub_channel.id) : []
    respond_to do |format|
      format.html
      format.csv do
        authorize :report, :export?
        audit_export
        send_data three_month_establishments_exporter.to_csv, **download_headers(three_months_mic_filename, "csv")
      end
      format.xlsx do
        authorize :report, :export?
        audit_export
        send_data three_month_establishments_exporter.to_xlsx, **download_headers(three_months_mic_filename, "xlsx")
      end
    end
  end

  def sub_channel
    @sub_channel = policy_scope(SubChannel).find_param!(params[:id])
    if @selected_channel && @sub_channel.channel_id != @selected_channel.id
      raise ActiveRecord::RecordNotFound
    end

    @scope = ReportScope.new(scope: Current.access_scope.narrow(sub_channel: @sub_channel))
    @selected_variation = params[:variation].to_s.presence_in(EstablishmentListingQuery::VARIATION_CLAUSES.keys)
    @selected_statuses = Array(params[:status]).map(&:to_s).compact_blank.uniq
    @selected_date_kinds = Array(params[:date_kind]).map(&:to_s) & EstablishmentListingQuery::DATE_KINDS.keys
    @from_date = parse_filter_date(params[:from_date])
    @to_date = parse_filter_date(params[:to_date])
    @query = params[:q].to_s.strip
    # A faixa de faturamento vem das duas alças e é normalizada pela própria consulta: a barra
    # precisa mostrar a mesma coisa que o filtro aplica.
    @min_revenue, @max_revenue = EstablishmentListingQuery.normalize_revenue_bounds(
      params[:min_revenue], params[:max_revenue]
    )
    @revenue_basis = EstablishmentListingQuery.normalize_revenue_basis(params[:revenue_basis])
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
      format.csv { authorize(:report, :export?); audit_export; send_data listing_exporter.to_csv, filename: listing_filename("csv"), type: "text/csv" }
      format.xlsx { authorize(:report, :export?); audit_export; send_data listing_exporter.to_xlsx, filename: listing_filename("xlsx"), type: Mime[:xlsx] }
    end
  end

  # Conteúdo do modal do calendário: os clientes que venderam num dia. Chega por Turbo Frame,
  # sem layout, e os carets do cabeçalho trocam o dia dentro do próprio frame.
  def weekly_day
    @period = calendar_period
    return head :not_found if @period.nil?

    @covered_days = covered_days_for(@period)
    @day = params[:day].to_i
    # URL editada à mão não derruba a tela nem vaza para o mês seguinte: fora da cobertura,
    # não há dia a mostrar.
    return head :not_found unless @day.between?(1, @covered_days)

    @date = @period + (@day - 1)
    @rows = @scope.day_companies(period: @period, day: @day)
    # Só a existência da anotação: o modal é apertado e o texto mora na ficha do cliente.
    @noted_cnpjs = policy_scope(CompanyNote).where(cnpj: @rows.map { |row| row["cnpj"] }).pluck(:cnpj).to_set
    @previous_day = @day > 1 ? @day - 1 : nil
    @next_day = @day < @covered_days ? @day + 1 : nil

    respond_to do |format|
      format.html { render partial: "reports/day_companies", layout: false }
      format.csv { authorize(:report, :export?); audit_export; send_data day_companies_exporter.to_csv, **download_headers(day_filename, "csv") }
      format.xlsx { authorize(:report, :export?); audit_export; send_data day_companies_exporter.to_xlsx, **download_headers(day_filename, "xlsx") }
    end
  end

  # Conteúdo do modal de lançamentos diários: chega por Turbo Frame, sem layout, com a mesma
  # janela e faixa de dias da tela que o abriu.
  # O modal soma os ECs do cliente, os mesmos que a linha da listagem soma. Cliente sem EC
  # neste MIC não tem lançamento para mostrar: é 404, como era para um EC de outro canal.
  def sub_channel_daily
    @sub_channel = policy_scope(SubChannel).find_param!(params[:id])
    @scope = ReportScope.new(scope: Current.access_scope.narrow(sub_channel: @sub_channel))
    @company = Company.find_param!(params[:company_id])
    @client = @scope.client_in_sub_channel(company_id: @company.id, sub_channel_id: @sub_channel.id)
    raise ActiveRecord::RecordNotFound if @client.establishment_ids.empty?

    @window = @scope.establishment_window(
      period: params[:period], from_day: params[:from_day], to_day: params[:to_day]
    )
    @rows = @scope.establishment_daily_revenues(
      establishment_ids: @client.establishment_ids, window: @window
    )

    render partial: "reports/daily_revenues", layout: false
  end

  private

  # O card do recorrente ordena por valores da janela inteira. O nome sai como string, então
  # A variação não é coluna da consulta: é a razão entre o mês atual e a base comparável.
  # Sem base não há percentual possível — a linha sai como nil e o ListingSort a manda para
  # o fim nos dois sentidos, como o NULLS LAST da ordenação em SQL.
  def sub_channel_sort_value(row)
    return row[@order.column].to_d unless @order.column == "variation"

    previous = row["previous_revenue"].to_d
    return if previous.zero?

    (row["current_revenue"].to_d - previous) / previous
  end

  # sort_rows recebe o texto e a comparação é alfabética; os demais são dinheiro.
  def recurring_sort_value(row)
    case @order.column
    when "name" then row[:name]
    when "last_month"
      closed_month = row[:months].reject { |month| month[:partial] }.max_by { |month| month[:period] }
      closed_month ? closed_month[:recurring] + closed_month[:accreditation] + closed_month[:accelerator] -
        closed_month[:reducer] : 0
    else row[:recurring_total] + row[:accreditation_total] + row[:adjustment_total]
    end
  end

  def indicator_sort_value(row)
    @order.column == "name" ? row[:name] : row[:risk_count]
  end

  # A linha da tela 3M é o subcanal, e cada mês da janela é uma coluna: ordenar por M0, M1
  # ou M2 é ordenar por aquele mês; "ECs no M0" e "prêmio" são valores da linha inteira.
  def three_month_order
    columns = { "prize" => "Prêmio de entrada", "accredited" => "ECs no M0" }
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
      min_revenue: @min_revenue, max_revenue: @max_revenue,
      revenue_basis: @revenue_basis,
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

  # Exportar é a operação de maior alcance da tela: larga a paginação e leva o recorte
  # inteiro. A trilha guarda o que foi pedido, não o que saiu — repetir o conteúdo aqui
  # faria da própria auditoria um vazamento.
  def audit_export
    Audit.record("report.export", request:,
      channel: @selected_channel,
      metadata: { tela: action_name, formato: request.format.symbol.to_s,
        escopo: Current.access_scope.cache_key })
  end

  def redirect_root_to_landing
    return unless request.path == root_path && !policy(:report).revenue?

    destination = landing_path
    redirect_to destination if destination && destination != root_path
  end

  def load_scope
    # O seletor de canal mostra só os Masters do escopo: oferecer um que responderia vazio
    # seria oferecer um caminho sem volta, e revelaria que ele existe.
    @channels = policy_scope(Channel).order(:name)
    @selected_channel = @channels.find_param!(params[:channel_id]) if params[:channel_id].present?
    @scope = ReportScope.new(scope: Current.access_scope.narrow(channel: @selected_channel))
    @cutoff_day = @scope.cutoff_day
  end

  # O MIC do filtro segue a regra do canal: uuid inexistente é 404, e MIC de outro Master que
  # o escolhido também — senão a tela responderia "nenhum cliente" para um recorte impossível,
  # que é uma resposta pior do que dizer que o endereço não existe.
  def selected_stalled_sub_channel
    return if params[:sub_channel_id].blank?

    sub_channel = policy_scope(SubChannel).find_param!(params[:sub_channel_id])
    raise ActiveRecord::RecordNotFound if @selected_channel &&
      sub_channel.channel_id != @selected_channel.id

    sub_channel
  end

  # Cabeçalho do download, num lugar só: o tipo sai do formato e o nome carrega o recorte.
  # Sem o recorte no nome, dois downloads seguidos chegam com o mesmo nome na pasta.
  def download_headers(basename, extension)
    content_type = extension == "csv" ? "text/csv" : Mime[:xlsx]
    { filename: "#{basename}.#{extension}", type: content_type }
  end

  def recurring_exporter
    RecurringEarningsExporter.new(@reports, channel_name: channel_name_or_nil)
  end

  def three_month_exporter
    ThreeMonthEarningsExporter.new(@reports, window: @window, channel_name: channel_name_or_nil)
  end

  def three_month_establishments_exporter
    ThreeMonthEstablishmentsExporter.new(@reports, window: @window,
      sub_channel_name: @sub_channel.name)
  end

  def weekly_exporter
    WeeklyRevenueExporter.new(@calendar, period: @period, channel_name: channel_name_or_nil)
  end

  def day_companies_exporter
    DayCompaniesExporter.new(@rows, date: @date)
  end

  def channel_name_or_nil
    helpers.channel_name(@selected_channel)
  end

  def three_months_mic_filename
    "ganhos-3m-#{@sub_channel.name.parameterize}"
  end

  def weekly_filename
    "ritmo-#{@period.strftime('%Y-%m')}"
  end

  def day_filename
    "clientes-do-dia-#{@date.strftime('%Y-%m-%d')}"
  end

  def stalled_exporter
    PreapprovedOffersExporter.new(@reports, sub_channel_name: @selected_sub_channel&.name)
  end

  def clover_filename
    return "clover-capital-ofertas" if @selected_sub_channel.nil?

    "clover-capital-#{@selected_sub_channel.name.parameterize}"
  end

  # A exportação repete o recorte da tela e larga a paginação: o arquivo é do filtro, não
  # da página que o usuário estava vendo.
  def listing_exporter
    rows = @scope.establishment_rows(
      sub_channel_id: @sub_channel.id, variation: @selected_variation,
      statuses: @selected_statuses, period: params[:period],
      from_day: params[:from_day], to_day: params[:to_day],
      date_kinds: @selected_date_kinds, from_date: @from_date, to_date: @to_date, query: @query,
      min_revenue: @min_revenue, max_revenue: @max_revenue,
      revenue_basis: @revenue_basis, sort: @sort, direction: @direction
    )
    EstablishmentListingExporter.new(rows, sub_channel_name: @sub_channel.name, window: @window)
  end

  def listing_filename(extension)
    "#{@sub_channel.name.parameterize}-estabelecimentos.#{extension}"
  end

  def parse_filter_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error, ArgumentError, TypeError
    nil
  end

  # O corpo da anotação é rich text e não entra no SQL da listagem: viria como HTML com
  # anexos dentro de uma consulta com GROUP BY. O trecho da tela sai daqui, numa query só,
  # pelo índice que o Action Text já mantém.
  def sub_channel_listing_params(overrides = {})
    {
      channel_id: @selected_channel&.uuid,
      variation: @selected_variation,
      status: @selected_statuses,
      date_kind: @selected_date_kinds,
      from_date: @from_date,
      to_date: @to_date,
      q: @query,
      min_revenue: @min_revenue,
      max_revenue: @max_revenue,
      revenue_basis: @revenue_basis,
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
