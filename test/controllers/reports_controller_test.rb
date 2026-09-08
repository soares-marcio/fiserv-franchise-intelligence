require "test_helper"
require "csv"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveRecord::Assertions::QueryAssertions

  test "trilha de navegação: agrupamento do menu não aparece, só páginas reais" do
    get stalled_reports_path

    assert_select "nav.breadcrumb-wrap a[href=?]", root_path, text: "Início"
    # "Dashboard" e "Operação" são agrupamentos da navbar, não páginas — não entram na
    # trilha nem como texto.
    assert_select "nav.breadcrumb-wrap li", text: /Dashboard/, count: 0
    assert_select "nav.breadcrumb-wrap span[aria-current=page]", text: "Mapa cliente"
  end

  test "cabeçalho mostra há quanto tempo a carteira recebeu arquivo" do
    get reports_path
    assert_select "a.header-status[data-tone=rose][href=?]", import_batches_path,
      text: /Sem arquivo importado/

    import_synthetic_workbook
    get reports_path
    assert_select "a.header-status[data-tone=green]", text: /Arquivo hoje/
  end

  test "o menu do header agrupa as páginas em submenus, com badge da idade do arquivo" do
    get reports_path

    # Dois grupos colapsáveis; o da página atual fica marcado no título.
    assert_select "nav.primary-nav details.nav-dropdown", count: 2
    assert_select "details.nav-dropdown summary.nav-link.is-active", text: /Dashboard/
    assert_select "details.nav-dropdown summary.nav-link", text: /Operação/
    assert_select ".nav-submenu a", text: /Faturamento/
    assert_select ".nav-submenu a", text: /Importar arquivo/
    assert_select "button.nav-toggle[aria-controls='primary_nav']"
    # Sem arquivo importado, o badge avisa em tom de alerta; com arquivo do dia, acalma.
    assert_select ".nav-badge[data-tone='rose']", text: /Nunca/

    import_synthetic_workbook
    get reports_path
    assert_select ".nav-badge[data-tone='green']", text: /Hoje/
  end

  test "a busca do header aponta para o endpoint de busca global" do
    get reports_path

    assert_select "body[data-app-layout-search-url-value=?]", search_path
    assert_select ".search-modal input.search-modal__input[aria-label]"
    assert_select ".search-modal turbo-frame#global-search[target=_top]"
  end

  test "clientes parados e semanal abrem com o banco recém-criado" do
    [ *AuditViews::ALIGNED_VIEWS, "audit_weekly_revenue" ].each do |view|
      ApplicationRecord.connection.execute("REFRESH MATERIALIZED VIEW #{view} WITH NO DATA")
    end

    get stalled_reports_path
    assert_response :success

    get weekly_reports_path
    assert_response :success
  end

  test "ganho recorrente abre vazio, e com dados mostra a série mensal" do
    get recurring_reports_path
    assert_response :success
    assert_select ".empty-state", text: /depende das colunas de volume/

    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views
    get recurring_reports_path
    assert_response :success
    assert_select "h1", text: "Ganho recorrente por subcanal"
    # A tela virou cards: o subcanal nomeia o card e a série fica na tabela interna.
    assert_select "article.earnings-card .earnings-card__name a", text: "MIC GAMA"
    assert_select "article.earnings-card tbody th[scope=row]", text: /ago\/2026/
    assert_no_match(/translation missing/i, response.body)
    assert_select "nav.breadcrumb-wrap span[aria-current=page]", text: "Ganho recorrente"
  end

  test "a página 3M abre sem volume importado e explica a dependência da planilha" do
    get three_months_reports_path
    assert_response :success
    assert_select "h1", text: "Ganhos 3M por subcanal"
    assert_select ".empty-state", text: /depende das colunas de volume da planilha/
  end

  test "a página 3M abre com o banco recém-criado, view de credenciamento sem dados" do
    ApplicationRecord.connection.execute(
      "REFRESH MATERIALIZED VIEW audit_accreditation_earnings WITH NO DATA"
    )
    get three_months_reports_path
    assert_response :success
  end

  # A janela vem do calendário, mas o link salvo com start_period continua valendo.
  test "o intervalo aplicado volta no calendário e escrito na tela" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get three_months_reports_path(from_date: "2026-06-01", to_date: "2026-08-15")

    assert_select "input[name=from_date][value=?]", "2026-06-01"
    assert_select "input[name=to_date][value=?]", "2026-08-01"
    assert_select "p", text: /Exibindo\s+Junho a agosto de 2026/
    # O link do subcanal precisa carregar a mesma janela, senão o nível 2 abre deslocado.
    assert_select ".earnings-card__name a[href*=?]", "from_date=2026-06-01"
  end

  test "link antigo com start_period continua abrindo a mesma janela" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get three_months_reports_path(start_period: "2026-06")

    assert_select "p", text: /Exibindo\s+Junho a agosto de 2026/
  end

  # O segundo seletor só oferece os dois meses seguintes ao M0, e escolher o primeiro
  # deles fecha a janela em dois meses — a tabela perde a coluna M2.
  # O intervalo das duas hipóteses de antecipação não cabe numa linha, e .metric-value corta
  # com reticências: sem o modificador, o card mostrava "R$ 6.54…" em vez do número.
  test "o adicional em intervalo ganha a classe que deixa o valor quebrar linha" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    # M0 de julho é a safra do EC credenciado na fixture; é a janela em que as duas
    # hipóteses de antecipação divergem e o card vira intervalo.
    get three_months_reports_path(start_period: "2026-07")

    assert_select "p.metric-value.metric-value--range", text: /–/
  end

  # O calendário abre na competência mais recente importada: abrir no mês do relógio
  # mostraria um calendário sem dado nenhum.
  test "o calendário do 3M abre ancorado na competência mais recente" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get three_months_reports_path

    assert_select "div[data-date-range-picker-open-on-value=?]", "2026-08-01"
    assert_select "button[aria-label=?]", "Ano anterior"
    assert_select "button[aria-label=?]", "Próximo ano"
  end

  test "o fim escolhido no calendário encurta a janela apurada" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get three_months_reports_path(from_date: "2026-06-10", to_date: "2026-07-22")

    assert_select ".earnings-card-bar__sort a.sort-link", text: /M0/
    assert_select "article.earnings-card th[scope=row]", text: /M0 · jun\/2026/
    assert_select ".earnings-card-bar__sort a.sort-link", text: /M1/
    assert_select "article.earnings-card th[scope=row]", text: /M1 · jul\/2026/
    assert_select ".earnings-card-bar__sort a.sort-link", text: /M2/, count: 0
    assert_select "p", text: /Exibindo\s+Junho a julho de 2026/
  end

  test "página 3M lista subcanais e navega para os cards de estabelecimento" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get three_months_reports_path
    assert_response :success
    assert_select ".earnings-card__name a", text: "MIC GAMA"
    # O locale precisa dos meses abreviados: %b sem abbr_month_names rendia
    # "Translation missing" em todos os rótulos de mês. M0 é o mês mais antigo.
    assert_select ".earnings-card-bar__sort a.sort-link", text: /M0/
    assert_select "article.earnings-card th[scope=row]", text: /M0 · jun\/2026/
    assert_select ".earnings-card-bar__sort a.sort-link", text: /M2/
    assert_select "article.earnings-card th[scope=row]", text: /M2 · ago\/2026/
    assert_no_match(/translation missing/i, response.body)

    sub_channel = SubChannel.find_by!(name: "MIC GAMA")
    # M0 = julho: é o mês de credenciamento do EC da fixture, e a janela avança dali.
    get three_months_sub_channel_report_path(id: sub_channel.uuid, start_period: "2026-07")
    assert_response :success
    assert_select ".metric-label", text: "EC 50000001"
    # Enquanto a classificação de antecipação está em definição, a tela não oferece
    # "com/sem": mostra o que é determinado e nomeia o intervalo do que não é.
    assert_select "body" do |body|
      assert_no_match(/Sem antecipação/, body.to_s)
      assert_match(/pendente da definição de antecipação/, body.to_s)
    end
  end

  test "renderiza a página de auditoria sem dados" do
    get reports_path
    assert_response :success
    assert_select "h1", text: "Auditoria de faturamento"
    assert_select "th", text: /Mês anterior cheio/
    assert_select "th", text: /Mês anterior comparável/
  end

  test "exporta CSV" do
    get reports_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Mês anterior (cheio)"
    assert_includes response.body, "Mês anterior comparável"
  end

  test "seleciona um canal e o preserva nas exportações" do
    selected = Channel.create!(external_id: "1", name: "CANAL A")
    Channel.create!(external_id: "2", name: "CANAL B")

    get reports_path(channel_id: selected.uuid)

    assert_response :success
    assert_select "select[name='channel_id'] option[selected]", text: "CANAL A"
    assert_select "select[name='channel_id'] option", text: "CANAL B"
    assert_select "a[href='#{reports_path(format: :csv, channel_id: selected.uuid)}']", text: "Exportar CSV"
    assert_select "a[href='#{reports_path(format: :xlsx, channel_id: selected.uuid)}']", text: "Exportar XLSX"
  end

  test "liga cada subcanal à sua listagem de estabelecimentos" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get reports_path

    assert_response :success
    assert_select "a[href='#{sub_channel_report_path(sub_channel)}']", text: "MIC A"
  end

  # O EC da listagem abre os lançamentos diários num modal; o conteúdo chega por Turbo
  # Frame, sem layout, com a mesma janela e faixa de dias da tela que o abriu.
  # As três colunas de valor ordenam a listagem pelo clique no rótulo; o link leva os
  # filtros junto e o sentido alterna a cada clique.
  test "as colunas de valor ordenam a listagem e anunciam o sentido" do
    import_synthetic_workbook
    refresh_audit_views
    sub_channel = SubChannel.find_by!(name: "MIC ALFA")

    get sub_channel_report_path(sub_channel)

    # A tela abre ordenada pelo mês anterior cheio e diz isso por escrito.
    assert_select "th[aria-sort=descending] a.sort-link.is-sorted", text: /Mês anterior cheio/
    assert_select ".table-toolbar__breakdown", text: /Ordenado por Mês anterior cheio, do maior para o menor/
    assert_select "th[aria-sort=none] a.sort-link", text: /Mês atual/
    # Coluna não ordenada mostra o ícone neutro: sem ele, ninguém descobre que dá clique.
    assert_select "a.sort-link .sort-indicator.is-idle svg.sort-icon", count: 2
    assert_select "a.sort-link.is-sorted .sort-indicator svg.sort-icon"
    # Sem ordenação escolhida não há por que oferecer volta ao padrão.
    assert_select ".sort-reset", count: 0

    get sub_channel_report_path(sub_channel, sort: "current_revenue", direction: "desc", q: "ALFA")

    assert_select "th[aria-sort=descending] a.sort-link.is-sorted", text: /Mês atual/
    # O segundo clique inverte e preserva a busca.
    assert_select "a.sort-link[href*=?]", "direction=asc"
    assert_select "a.sort-link[href*=?]", "q=ALFA"
    # E há caminho de volta, levando a busca junto.
    assert_select "a.sort-reset[href*=?]", "q=ALFA"
    assert_select "a.sort-reset[href*=?]", "sort=", count: 0
  end

  # O quinto card traz o ticket médio da carteira, com o divisor escrito: a conta mistura o
  # mês fechado com o status de hoje, e sem a explicação vira outra coisa na cabeça de quem lê.
  test "a tela do subcanal mostra o ticket médio e o divisor" do
    import_synthetic_workbook
    refresh_audit_views
    sub_channel = SubChannel.find_by!(name: "MIC ALFA")

    get sub_channel_report_path(sub_channel)

    assert_response :success
    assert_select ".metric-card .metric-label", text: "Ticket médio"
    assert_select ".metric-card .metric-hint", text: /Mês anterior cheio ÷ 1 CNPJ ativo/
  end

  # A barra da tabela diz quantos ECs do recorte estão ativos e quantos suspensos.
  test "a barra da listagem mostra ativos e suspensos do recorte" do
    import_synthetic_workbook
    refresh_audit_views
    sub_channel = SubChannel.find_by!(name: "MIC ALFA")

    get sub_channel_report_path(sub_channel)

    assert_response :success
    # Em MIC ALFA a fixture tem dois ECs no mesmo CNPJ, ambos ativos: o badge conta os dois
    # ECs, e a composição conta o cliente uma vez. É a diferença de unidade, na prática.
    assert_select ".badge", text: /2 ECs/
    assert_select ".table-toolbar__breakdown", text: /1 ativos.*0 suspensos.*por CNPJ/m
    # Cada contagem carrega a regra em tooltip, para a tela explicar sozinha.
    assert_select ".table-toolbar__breakdown .tooltip[data-tip*=?]", "pelo menos um EC ativo"
    assert_select ".table-toolbar__breakdown .tooltip[data-tip*=?]", "todos os ECs suspensos"
  end

  test "lançamentos diários do EC chegam sem layout, um dia por linha" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    establishment = Establishment.find_by!(ec: "11111111")

    get sub_channel_daily_report_path(sub_channel, establishment, channel_id: channel.uuid)

    assert_response :success
    assert_select "turbo-frame#daily_revenues"
    assert_select "body", false, "o modal chega sem layout"
    assert_select "h2", text: "EC 11111111"
    assert_select "tbody th[scope=?]", "row", text: "24"
    # brl usa espaço não separável entre o símbolo e o número; o regex evita a armadilha.
    assert_select "td", text: /100,00/
    assert_select "td", text: /80,00/
  end

  # Três competências no banco é o estado da operação real: cada planilha traz duas, e a
  # mais antiga fica das importações passadas. A coluna do penúltimo mês só existe nesse caso.
  test "com a penúltima competência coberta, o modal mostra os três meses" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    establishment = Establishment.find_by!(ec: "11111111")
    cover_penultimate_period(channel, establishment, Date.new(2026, 6, 1), amount: 60)

    get sub_channel_daily_report_path(sub_channel, establishment, channel_id: channel.uuid)

    assert_response :success
    assert_select "thead th", count: 4, message: "Dia mais as três competências"
    assert_select "thead th", text: "junho de 2026"
    assert_select "thead th", text: "julho de 2026"
    assert_select "thead th", text: "agosto de 2026"
    # O valor tem que sair na coluna certa: é a soma da penúltima competência, não de outra.
    assert_select "tfoot td:first-of-type", text: /60,00/
    assert_select "tfoot td", count: 3
  end

  # A faixa de dias da tela não recorta o modal: ele espelha a planilha, que traz
  # DIA 01..DIA 31 das duas competências.
  test "lançamentos diários trazem o mês inteiro mesmo com a tela filtrada" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    establishment = Establishment.find_by!(ec: "11111111")

    get sub_channel_daily_report_path(sub_channel, establishment,
      channel_id: channel.uuid, from_day: 1, to_day: 10)

    assert_response :success
    assert_select "tbody th[scope=?]", "row", count: 31
    assert_select "tbody th[scope=?]", "row", text: "24"
  end

  test "mostra os estabelecimentos que compõem os totais do subcanal" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid)

    assert_response :success
    # O título da página é o canal; o subcanal nomeia a tabela logo abaixo.
    assert_select "h1", text: "CANAL A"
    assert_select "h2", text: "MIC A"
    assert_select "th", text: /Mês anterior cheio/
    assert_select "th", text: /Mês anterior comparável/
    assert_select "td", text: /11111111/
    assert_select "td", text: "12.345.678/0001-91"
    assert_select "td", text: /LOJA UM/
    assert_select "th", text: "Datas do ciclo"
    assert_select "dt", text: "Cred."
    assert_select "dt", text: "Ativ."
    assert_select "dt", text: "Susp."
    assert_select "dd", text: "15/03/2024"
    assert_select "dd", text: "02/04/2024"
    # Sob o EC: NET MDR truncado (0,299 nunca vira 0,30) e os equipamentos do Mapa.
    assert_select ".ec-meta p", text: "NET MDR 0,29%"
    assert_select ".ec-meta p", text: "Link pgto · 2 POS"
    assert_select "tfoot", false
    assert_select "input[name='status[]']"
    assert_select "input[name='date_kind[]']"
    assert_select "input[name='from_date']"
    assert_select "input[name='to_date']"
    assert_select "input[name='q']"
    assert_select "a", text: "10"
    assert_select "a", text: "20"
    assert_select "a", text: "50"
    assert_select "a", text: "100"
    assert_select "[data-controller='tag-select']"
    assert_select "[data-controller='date-range-picker']"
    assert_select "#status_filter_trigger[role='combobox'][aria-controls='status_filter_menu']"
    assert_select "#date_kind_filter_trigger[role='combobox'][aria-controls='date_kind_filter_menu']"
    assert_select "#date_range_panel[role='dialog']"
    assert_select "input#status_Active[data-label='Ativo'][data-tone='success']"
    assert_select "button", text: "Limpar datas"
    assert_select "button", text: "Concluir"
    assert_select "a[href='#{reports_path(channel_id: channel.uuid)}']"
    # A coluna de lançamentos diários e o modal saíram: sem serventia para o usuário.
    assert_select "dialog.modal", false
    assert_select "button", text: "Lançamentos", count: 0
    assert_select ".variation-chip--up [data-tip=?]", "Subiu"
    assert_select "table tbody td span.block", false
    # Abas de variação com contagens, e a completa ativa por padrão.
    assert_select "nav.variation-tabs a", count: 3
    assert_select "nav.variation-tabs a.is-active", text: /Todos/
    # Cada aba descreve o próprio critério, em palavras, com o glifo de tendência no título.
    assert_select "nav.variation-tabs .tab-title .variation-icon", count: 2
    assert_select "nav.variation-tabs .tab-hint", text: "vendeu mais, manteve ou é novo"
    assert_select "nav.variation-tabs .tab-hint", text: "vendeu menos, está sem venda ou voltou do zero"
  end

  test "abas de variação separam alta e baixa, com EC zerado na baixa" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    # Segundo EC: faturou no mês anterior e zerou o atual — a regra manda para a Baixa.
    zeroed = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    batch = ImportBatch.find_by!(channel:)
    RevenueSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment: zeroed,
      legal_name: "LOJA DOIS LTDA", trade_name: "LOJA DOIS", contract_status: "Active",
      previous_month_total: 60, current_month_total: 0
    )
    DailyRevenueConsolidated.create!(
      establishment: zeroed, channel:, period: Date.new(2026, 7, 1), day: 10, amount: 60,
      provisional: false, source_import_batch_id: batch.id, revised_count: 0
    )

    # Terceiro EC: ativação antiga, zerado no mês anterior e vendendo agora — não é
    # crescimento, é retomada: mora na queda, com o chip descritivo próprio.
    returned = Establishment.create!(
      ec: "33333333", company: Company.create!(cnpj: "12345678000193"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment: returned,
      legal_name: "LOJA TRES LTDA", trade_name: "LOJA TRES", contract_status: "Active",
      previous_month_total: 0, current_month_total: 40
    )
    MapSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment: returned,
      legal_name: "LOJA TRES LTDA", trade_name: "LOJA TRES", contract_status: "Active",
      accredited_on: Date.new(2024, 1, 10), activated_on: Date.new(2024, 2, 1)
    )
    DailyRevenueConsolidated.create!(
      establishment: returned, channel:, period: Date.new(2026, 8, 1), day: 10, amount: 40,
      provisional: true, source_import_batch_id: batch.id, revised_count: 0
    )

    # Na semente, o EC 11111111 sobe (80 → 100): fica em crescimento.
    get sub_channel_report_path(sub_channel, variation: "alta")
    assert_response :success
    assert_select "nav.variation-tabs a.is-active .tab-title", text: /Em crescimento · 1/
    assert_select "tbody td", text: /11111111/
    assert_select "tbody td", text: "22222222", count: 0
    assert_select "tbody td", text: "33333333", count: 0

    get sub_channel_report_path(sub_channel, variation: "baixa")
    assert_response :success
    assert_select "nav.variation-tabs a.is-active .tab-title", text: /Em queda · 2/
    assert_select "tbody td", text: "22222222"
    assert_select "tbody td", text: "33333333"
    assert_select "tbody td", text: /11111111/, count: 0
    assert_select ".variation-chip", text: /Voltou a vender/
  end

  test "os cards da primeira dobra somam a aba ativa, com o recorte rotulado" do
    template = BinImport::Template.register!
    _channel, sub_channel = seed_subchannel_revenue(template)

    # Sem aba: o subcanal inteiro (o único EC da semente fatura 100 no mês atual).
    get sub_channel_report_path(sub_channel)
    assert_select ".metric-value", text: "R$\u00A0100,00"

    # Na Alta o mesmo EC continua; na Baixa (vazia) os cards zeram junto com a tabela,
    # e o rótulo diz o recorte — na Alta a variação é positiva por construção.
    get sub_channel_report_path(sub_channel, variation: "alta")
    assert_select ".metric-value", text: "R$\u00A0100,00"
    # A variação verdadeira do subcanal fica ancorada ao lado da enviesada da aba.
    assert_select ".metric-hint", text: /Somando só a aba Em crescimento \(1 ECs\).*Subcanal inteiro:.*\+25,0%/m

    get sub_channel_report_path(sub_channel, variation: "baixa")
    assert_select ".metric-value", text: "R$\u00A0100,00", count: 0
    assert_select ".metric-value", text: "R$\u00A00,00"
    assert_select ".metric-hint", text: /Somando só a aba Em queda \(0 ECs\)/
    assert_select ".empty-state"
  end

  test "filtra a listagem de estabelecimentos por status e faixa de dias" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    suspended = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: ImportBatch.find_by!(channel:), channel:, sub_channel:,
      establishment: suspended, legal_name: "LOJA DOIS LTDA", trade_name: "LOJA DOIS",
      contract_status: "Suspended", previous_month_total: 20, current_month_total: 30
    )

    get sub_channel_report_path(
      sub_channel, channel_id: channel.uuid, status: [ "Active" ],
      date_kind: [ "credenciamento" ], from_date: "2024-03-01", to_date: "2024-03-31"
    )

    assert_response :success
    assert_select "td", text: /11111111/
    assert_select "td", text: "22222222", count: 0
    assert_select "input#status_Active[checked]"
    assert_select "input#date_kind_credenciamento[checked]"
    assert_select "input[name='from_date'][value='2024-03-01']"
  end

  test "busca e pagina a listagem de estabelecimentos" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    second = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: ImportBatch.find_by!(channel:), channel:, sub_channel:,
      establishment: second, legal_name: "LOJA DOIS LTDA", trade_name: "LOJA DOIS",
      contract_status: "Active", previous_month_total: 20, current_month_total: 30
    )

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, q: "loja dois")

    assert_response :success
    assert_select "td", text: "22222222"
    assert_select "td", text: /11111111/, count: 0
    assert_select "input[name='q'][value='loja dois']"

    get sub_channel_report_path(
      sub_channel, channel_id: channel.uuid, per_page: 1, page: 2
    )

    assert_response :success
    assert_select "td", text: "22222222"
    assert_select "td", text: /11111111/, count: 0
    assert_select "a", text: "Anterior"
    assert_select "a", text: "Próxima"
  end

  # A tela de subcanal é a que tem filtros, abas e paginação — e era a única sem exportação.
  # O arquivo leva o recorte da tela inteiro, menos a paginação: exportar só a página seria
  # entregar um recorte que ninguém pediu.
  test "exporta a listagem do subcanal em CSV com todas as linhas do recorte" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    seed_second_establishment(channel, sub_channel)

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, per_page: 1, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    table = CSV.parse(response.body, headers: true)

    assert_equal EstablishmentListingExporter::HEADERS, table.headers
    assert_equal [ "11111111", "22222222", "TOTAL" ], table.map { |row| row["EC"] }
    assert_equal "12.345.678/0001-91", table[0]["CNPJ"]
    assert_equal "LOJA UM", table[0]["Nome fantasia"]
    assert_equal "Ativo", table[0]["Status do contrato"]
    assert_equal "15/03/2024", table[0]["Credenciamento"]
    assert_equal "80.0", table[0]["Mês anterior (cheio)"]
    assert_equal "100.0", table[0]["Mês atual"]
  end

  test "a exportação respeita a busca e a aba escolhidas na tela" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    seed_second_establishment(channel, sub_channel)

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, q: "loja dois", format: :csv)
    ecs = CSV.parse(response.body, headers: true).map { |row| row["EC"] }

    assert_equal [ "22222222", "TOTAL" ], ecs

    # A segunda loja não tem faturamento diário consolidado: cai na aba de queda.
    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, variation: "baixa", format: :csv)

    assert_equal [ "22222222", "TOTAL" ], CSV.parse(response.body, headers: true).map { |row| row["EC"] }
  end

  # A exportação não tem página: montar a listagem paginada antes de responder era rodar o SQL
  # mais caro do app três vezes (resumo, página que ninguém vê, e as linhas do arquivo).
  test "a exportação roda a consulta da listagem uma vez só" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    assert_queries_match(/LEFT JOIN LATERAL/, count: 1) do
      get sub_channel_report_path(sub_channel, channel_id: channel.uuid, format: :csv)
    end
    assert_response :success
  end

  # period_coverages é lida para o corte do cabeçalho e para os períodos da janela; a tela e
  # a exportação reaproveitam as duas leituras em vez de repeti-las a cada chamada do scope.
  test "a tela do subcanal lê period_coverages duas vezes, e a exportação também" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    assert_queries_match(/FROM period_coverages/, count: 2) do
      get sub_channel_report_path(sub_channel, channel_id: channel.uuid)
    end
    assert_queries_match(/FROM period_coverages/, count: 2) do
      get sub_channel_report_path(sub_channel, channel_id: channel.uuid, format: :csv)
    end
  end

  test "exporta a listagem do subcanal em XLSX" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, format: :xlsx)

    assert_response :success
    assert_equal Mime[:xlsx].to_s, response.media_type
    assert_includes response.headers["Content-Disposition"], "mic-a"
  end

  test "a tela de subcanal oferece os dois formatos preservando o recorte" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, variation: "alta", q: "loja")

    assert_response :success
    %w[csv xlsx].each do |format|
      href = css_select("a[href*='.#{format}?']").first["href"]

      assert_includes href, "channel_id=#{channel.uuid}"
      assert_includes href, "variation=alta"
      assert_includes href, "q=loja"
      # A janela de comparação faz parte do recorte; a paginação, não.
      assert_includes href, "from_day="
      assert_not_includes href, "page="
    end
  end

  # As abas são links que trocam de página, não painéis de um widget: com role="tab" o
  # leitor de tela anuncia um tablist e espera setas e tabpanel, que não existem.
  test "as abas de variação se anunciam como navegação, com a atual marcada" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, variation: "baixa")

    assert_response :success
    assert_select "nav.variation-tabs[role='tablist']", count: 0
    assert_select "nav.variation-tabs a[role='tab']", count: 0
    assert_select "nav.variation-tabs a[aria-current='page']", count: 1
    assert_select "nav.variation-tabs a[aria-current='page'] .tab-title", text: /Em queda/
  end

  test "responde não encontrado para subcanal desconhecido" do
    get sub_channel_report_path(id: SecureRandom.uuid)
    assert_response :not_found
  end

  private

  def seed_second_establishment(channel, sub_channel)
    second = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: ImportBatch.find_by!(channel:), channel:, sub_channel:,
      establishment: second, legal_name: "LOJA DOIS LTDA", trade_name: "LOJA DOIS",
      contract_status: "Active", previous_month_total: 20, current_month_total: 30
    )
    second
  end

  # A terceira competência do modal não vem do arquivo atual: no banco real ela ficou das
  # importações anteriores. Aqui bastam a cobertura e um lançamento.
  def cover_penultimate_period(channel, establishment, period, amount:)
    now = Time.current
    batch_id = ImportBatch.last.id
    PeriodCoverage.upsert_all(
      [ { channel_id: channel.id, period:, max_known_day: 30, closed: true,
          last_import_batch_id: batch_id, created_at: now, updated_at: now } ],
      unique_by: "index_period_coverages_on_channel_id_and_period"
    )
    DailyRevenueConsolidated.upsert_all(
      [ { establishment_id: establishment.id, channel_id: channel.id, period:, day: 24, amount:,
          provisional: false, source_import_batch_id: batch_id, revised_count: 0,
          created_at: now, updated_at: now } ],
      unique_by: "index_daily_revenues_consolidated_primary"
    )
  end

  def seed_subchannel_revenue(template)
    channel = Channel.create!(external_id: "A", name: "CANAL A")
    company = Company.create!(cnpj: "12345678000191")
    establishment = Establishment.create!(ec: "11111111", company:, channel:)
    sub_channel = channel.sub_channels.create!(name: "MIC A")
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "a.xlsx",
      file_checksum: "checksum-reports-#{SecureRandom.hex(4)}",
      previous_period: Date.new(2026, 7, 1), current_period: Date.new(2026, 8, 1),
      current_month_cutoff_day: 24, status: "validated"
    )
    RevenueSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      legal_name: "LOJA UM LTDA", trade_name: "LOJA UM", contract_status: "Active",
      previous_month_total: 80, current_month_total: 100
    )
    MapSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      legal_name: "LOJA UM LTDA", trade_name: "LOJA UM", contract_status: "Active",
      accredited_on: Date.new(2024, 3, 15), activated_on: Date.new(2024, 4, 2),
      has_payment_link: true, smart_pos_count: 2, other_pos_count: 0, net_mdr: 0.299
    )
    now = Time.current
    PeriodCoverage.upsert_all(
      [
        {
          channel_id: channel.id, period: Date.new(2026, 7, 1), max_known_day: 31, closed: true,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        },
        {
          channel_id: channel.id, period: Date.new(2026, 8, 1), max_known_day: 24, closed: false,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        }
      ],
      unique_by: "index_period_coverages_on_channel_id_and_period"
    )
    DailyRevenueConsolidated.upsert_all(
      [
        {
          establishment_id: establishment.id, channel_id: channel.id, period: Date.new(2026, 7, 1),
          day: 24, amount: 80, provisional: false, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        },
        {
          establishment_id: establishment.id, channel_id: channel.id, period: Date.new(2026, 8, 1),
          day: 24, amount: 100, provisional: true, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        }
      ],
      unique_by: "index_daily_revenues_consolidated_primary"
    )
    [ channel, sub_channel ]
  end
end
