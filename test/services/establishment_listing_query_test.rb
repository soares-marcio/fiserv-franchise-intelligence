require "test_helper"

# Caracterização da listagem por subcanal: fixa o contrato (linhas, totais, abas, filtros e
# paginação) antes de qualquer otimização da consulta.
class EstablishmentListingQueryTest < ActiveSupport::TestCase
  ALFA = "MIC ALFA".freeze
  REVENUE_COLUMNS = %w[previous_full_revenue previous_revenue current_revenue].freeze

  setup do
    @batch = import_synthetic_workbook(lojas: lojas)
    @sub_channel = SubChannel.find_by!(name: ALFA)
    # A planilha sintética ativa todo mundo em fevereiro; a NOVA precisa ter sido ativada
    # dentro da janela comparada para contar como "Novo" em vez de "Voltou a vender".
    MapSnapshot.joins(:establishment).where(establishments: { ec: "30000005" })
      .update_all(activated_on: Date.new(2026, 8, 3))
  end

  # A tela abre pelo mês anterior cheio, do maior para o menor: 1.000, 400, 50 e dois
  # zerados desempatados por EC. Ordem por EC não respondia a nenhuma pergunta.
  test "lista os ECs do subcanal na ordem padrão, com contagens por aba" do
    page = listing

    assert_equal %w[30000001 30000003 30000002 30000004 30000005], page.rows.map { |row| row["ec"] }
    assert_equal 5, page.total_count
    assert_equal({ todas: 5, alta: 2, baixa: 3 }, page.variation_counts)
    assert_equal [ 1, EstablishmentListingQuery::DEFAULT_PER_PAGE ], [ page.page, page.per_page ]
    assert_nil page.overall_totals
  end

  # Decisão do usuário (07/09/2026): a aba conta estabelecimentos, identificados pelo CNPJ;
  # a listagem continua mostrando um EC por linha. Dois ECs do mesmo CNPJ são um
  # estabelecimento na contagem e duas linhas na tabela.
  test "abas contam estabelecimentos distintos por CNPJ; a listagem lista um EC por linha" do
    irmao = loja("30000006", "11222333000181", "ALFA LANCHES II",
      dias_m1: { 1 => 10 }, dias_atual: { 1 => 20 })
    import_synthetic_workbook(lojas: lojas + [ irmao ], filename: "BIN_TESTE_20260812.xlsx")

    page = listing

    assert_equal 6, page.rows.size, "cada EC é uma linha"
    assert_equal 6, page.total_count, "a paginação conta linhas, não empresas"
    assert_equal 5, page.variation_counts[:todas],
      "os dois ECs do mesmo CNPJ contam um estabelecimento"
  end

  # A barra conta CNPJs, não ECs: a suspensão é do cliente. As contagens seguem a aba e os
  # demais filtros; status sem ninguém volta zerado, porque quem lê a barra precisa do zero.
  test "conta ativos e suspensos do recorte, por CNPJ" do
    assert_equal({ "Active" => 4, "Suspended" => 1 }, listing.status_counts)
    # A aba Em queda tem três: ALFA EXPRESS (caiu), ALFA RETORNO (voltou do zero) e a
    # suspensa, que não vendeu.
    assert_equal({ "Active" => 2, "Suspended" => 1 }, listing(variation: "baixa").status_counts)
    assert_equal({ "Active" => 1, "Suspended" => 0 }, listing(query: "ALFA EXPRESS").status_counts)
  end

  # Decisão do usuário (07/09/2026): o CNPJ é ativo se ao menos um EC estiver ativo, e só
  # entra em suspensos quando todos os ECs dele estão suspensos. Na carteira real, oito dos
  # nove CNPJs com status misto são troca de EC — o antigo suspenso, o novo aberto no lugar.
  test "CNPJ com um EC ativo e outro suspenso conta como ativo" do
    misto = lojas + [ loja("30000006", "11222333000181", "ALFA LANCHES II",
      contract_status: "Suspended", dias_m1: { 1 => 10 }, dias_atual: { 1 => 20 }) ]
    import_synthetic_workbook(lojas: misto, filename: "BIN_TESTE_20260812.xlsx")

    counts = listing.status_counts

    assert_equal 4, counts["Active"], "o CNPJ com um EC ativo continua ativo"
    assert_equal 1, counts["Suspended"], "só a ALFA SUSPENSA tem todos os ECs suspensos"
  end

  # A data do último acesso ao app entra nas datas do ciclo. Não é enfeite: a view
  # audit_accreditation_earnings condiciona o prêmio de entrada a ter havido acesso ao app,
  # então a tela precisa deixar ver quem acessou e quando.
  #
  # A asserção é contra a data literal da planilha de propósito: a planilha traz horário de
  # Brasília e a coluna o guarda sem converter, então só a leitura crua devolve o dia certo.
  # Ver o comentário na view do subcanal.
  test "traz a data de uso do app de cada EC" do
    linhas = listing.rows.index_by { |row| row["ec"] }

    assert_equal Date.new(2026, 8, 20), linhas["30000001"]["last_app_access_at"].to_date
    assert_nil linhas["30000002"]["last_app_access_at"], "EC sem acesso no Mapa não inventa data"
  end

  # As três colunas de valor podem ordenar a listagem; o EC continua sendo o critério de
  # desempate, senão a paginação embaralha linhas de mesmo valor entre páginas.
  test "ordena pelas colunas de valor, nos dois sentidos" do
    por_atual = listing(sort: "current_revenue", direction: "desc").rows.map { |row| row["ec"] }
    assert_equal %w[30000001 30000004 30000005 30000002 30000003], por_atual

    # Os cinco valores são distintos, então crescente é a lista invertida.
    assert_equal por_atual.reverse,
      listing(sort: "current_revenue", direction: "asc").rows.map { |row| row["ec"] }

    # Mês anterior cheio: 1.000 (ALFA LANCHES), 400 (SUSPENSA), 50 (EXPRESS) e dois zerados,
    # que caem no fim desempatados por EC.
    por_anterior = listing(sort: "previous_full_revenue", direction: "desc").rows.map { |row| row["ec"] }
    assert_equal %w[30000001 30000003 30000002 30000004 30000005], por_anterior
  end

  test "coluna desconhecida ou sentido inválido caem na ordem padrão" do
    padrao = listing.rows.map { |row| row["ec"] }

    assert_equal padrao, listing(sort: "cnpj; DROP TABLE").rows.map { |row| row["ec"] }
    assert_equal padrao, listing(sort: nil, direction: "desc").rows.map { |row| row["ec"] }
    # Sentido inválido com coluna válida vale como desc, que é o primeiro clique na tela.
    assert_equal listing(sort: "current_revenue", direction: "desc").rows.map { |row| row["ec"] },
      listing(sort: "current_revenue", direction: "seja lá o que for").rows.map { |row| row["ec"] }
  end

  # Ticket médio da carteira: mês anterior cheio dividido pelos CNPJs ativos do recorte
  # (decisão do usuário, 08/09/2026). Mistura o mês fechado com o status de hoje de
  # propósito — é "quanto rende cada cliente ativo" —, e por isso a tela escreve o divisor.
  test "ticket médio divide o mês anterior cheio pelos CNPJs ativos" do
    page = listing

    ativos = page.status_counts["Active"]
    assert_equal 4, ativos
    assert_in_delta page.totals[:previous_full_revenue] / ativos, page.average_ticket, 0.01
  end

  test "sem CNPJ ativo no recorte, o ticket médio não existe" do
    page = listing(query: "ALFA SUSPENSA")

    assert_equal 0, page.status_counts["Active"]
    assert_nil page.average_ticket
  end

  test "alinha os dois meses pela mesma faixa de dias e mantém o mês anterior cheio" do
    row = listing.rows.find { |candidate| candidate["ec"] == "30000001" }
    loja = lojas.first

    assert_equal loja.total_m1, row["previous_full_revenue"].to_d
    assert_equal loja.dias_m1.select { |day, _| day <= cutoff }.values.sum, row["previous_revenue"].to_d
    assert_equal loja.total_atual, row["current_revenue"].to_d
    assert_equal cutoff, row["max_known_day"].to_i
  end

  test "totais da aba são a soma das linhas quando tudo cabe em uma página" do
    [ nil, "alta", "baixa" ].each do |variation|
      page = listing(variation:)

      REVENUE_COLUMNS.each do |column|
        expected = page.rows.sum { |row| row[column].to_d }
        assert_equal expected, page.totals.fetch(column.to_sym), "#{column} na aba #{variation || 'todas'}"
      end
    end
  end

  test "aba alta traz quem cresceu ou é novo; aba baixa quem caiu, zerou ou voltou a vender" do
    assert_equal %w[30000001 30000005], listing(variation: "alta").rows.map { |row| row["ec"] }
    # Ordem padrão dentro da aba: 400 (SUSPENSA), 50 (EXPRESS) e o zerado (RETORNO).
    assert_equal %w[30000003 30000002 30000004], listing(variation: "baixa").rows.map { |row| row["ec"] }
  end

  test "contagens por aba ignoram a aba ativa e os totais gerais ancoram a variação" do
    todas = listing
    alta = listing(variation: "alta")

    assert_equal todas.variation_counts, alta.variation_counts
    assert_equal 2, alta.total_count
    assert_equal todas.totals.slice(:previous_revenue, :current_revenue), alta.overall_totals
  end

  test "pagina e normaliza página e tamanho fora das opções" do
    segunda = listing(page: 2, per_page: 2)
    assert_equal %w[30000002 30000004], segunda.rows.map { |row| row["ec"] }
    assert_equal [ 2, 2, 3 ], [ segunda.page, segunda.per_page, segunda.total_pages ]

    alem = listing(page: 99, per_page: 2)
    assert_equal [ 3, %w[30000005] ], [ alem.page, alem.rows.map { |row| row["ec"] } ]

    assert_equal EstablishmentListingQuery::DEFAULT_PER_PAGE, listing(per_page: 0).per_page
    assert_equal EstablishmentListingQuery::PER_PAGE_OPTIONS.max, listing(per_page: 1000).per_page
  end

  test "filtra por status do contrato" do
    page = listing(statuses: [ "Suspended", "" ])

    assert_equal %w[30000003], page.rows.map { |row| row["ec"] }
    assert_equal({ todas: 1, alta: 0, baixa: 1 }, page.variation_counts)
  end

  test "filtra por intervalo de datas, aceita intervalo invertido e vale para os três tipos sem marcação" do
    ativadas = listing(date_kinds: [ "ativacao" ], from_date: "2026-08-01", to_date: "2026-08-31")
    assert_equal %w[30000005], ativadas.rows.map { |row| row["ec"] }

    invertido = listing(date_kinds: [ "ativacao" ], from_date: "2026-08-31", to_date: "2026-08-01")
    assert_equal %w[30000005], invertido.rows.map { |row| row["ec"] }

    # Sem tipo marcado o intervalo vale para credenciamento, ativação ou suspensão; todos
    # foram credenciados em fevereiro, então todos entram.
    fevereiro = listing(from_date: "2026-02-01", to_date: "2026-02-28")
    assert_equal 5, fevereiro.total_count

    assert_equal 5, listing(from_date: "2026-08-01").total_count, "só um lado do intervalo não filtra"
  end

  test "busca por EC, CNPJ formatado e nome, sem distinguir maiúsculas" do
    { "30000003" => "EC", "33.444.555/0001-30" => "CNPJ formatado", "alfa suspensa" => "nome" }
      .each do |query, kind|
      assert_equal %w[30000003], listing(query:).rows.map { |row| row["ec"] }, "por #{kind}"
    end
    assert_equal 0, listing(query: "zzz").total_count
  end

  test "janela mais curta recorta os dois meses" do
    page = listing(window: window(to_day: 2))
    row = page.rows.find { |candidate| candidate["ec"] == "30000001" }

    assert_equal 300, row["previous_revenue"].to_d
    assert_equal 200, row["current_revenue"].to_d
    assert_equal 1000, row["previous_full_revenue"].to_d
  end

  test "página vazia tem a mesma forma de uma página cheia" do
    page = EstablishmentListingQuery.empty_page

    assert_equal [ [], 0, 1, 1 ], [ page.rows, page.total_count, page.page, page.total_pages ]
    assert_equal({ todas: 0, alta: 0, baixa: 0 }, page.variation_counts)
    assert_equal REVENUE_COLUMNS.map(&:to_sym), page.totals.keys
  end

  private

  def listing(window: self.window, **options)
    EstablishmentListingQuery.new(
      channel_id: @batch.channel_id, sub_channel_id: @sub_channel.id, window:, **options
    ).call
  end

  def window(to_day: cutoff)
    PeriodWindow.new(period: BinWorkbook::CURRENT_PERIOD, from_day: 1, to_day:, max_day: cutoff)
  end

  def cutoff
    BinWorkbook.cutoff_day(lojas)
  end

  # Cinco ECs no MIC ALFA cobrindo cada classificação das abas, e um no MIC BETA que nunca
  # pode aparecer. Os valores esperados saem destes dados, não de números fixados nos testes.
  def lojas
    @lojas ||= [
      loja("30000001", "11222333000181", "ALFA LANCHES", dias_m1: { 1 => 100, 2 => 200, 25 => 700 },
        dias_atual: { 1 => 150, 2 => 50, 10 => 300 }, proposta: true,
        app_access_at: "2026-08-20 14:30"),
      loja("30000002", "22333444000105", "ALFA EXPRESS", dias_m1: { 1 => 50 }, dias_atual: { 1 => 10, 2 => 20 }),
      loja("30000003", "33444555000130", "ALFA SUSPENSA", contract_status: "Suspended",
        dias_m1: { 1 => 400 }, dias_atual: {}),
      loja("30000004", "44555666000172", "ALFA RETORNO", dias_m1: {}, dias_atual: { 5 => 80 }),
      loja("30000005", "55666777000109", "ALFA NOVA", dias_m1: {}, dias_atual: { 3 => 60 }),
      loja("40000001", "66777888000156", "BETA CAFE", sub_channel_name: "MIC BETA",
        dias_m1: { 1 => 900 }, dias_atual: { 1 => 900 })
    ]
  end

  def loja(ec, cnpj, trade_name, sub_channel_name: ALFA, contract_status: "Active", proposta: false,
    app_access_at: nil, dias_m1:, dias_atual:)
    BinWorkbook::Loja.new(
      ec:, cnpj:, sub_channel_name:, legal_name: "#{trade_name} LTDA", trade_name:,
      contract_status:, dias_m1:, dias_atual:, proposta:, app_access_at:
    )
  end
end
