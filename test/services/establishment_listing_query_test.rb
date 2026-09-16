require "test_helper"

# Caracterização da listagem por subcanal: fixa o contrato (linhas, totais, abas, filtros e
# paginação). A linha é o cliente, identificado pelo CNPJ, e soma o faturamento de todos os
# ECs dele — as asserções de soma existem para que um filtro nunca volte a recortar a soma.
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
  # zerados desempatados por CNPJ. Ordem por EC não respondia a nenhuma pergunta.
  test "lista um cliente por linha na ordem padrão, com contagens por aba" do
    page = listing

    assert_equal [ "ALFA LANCHES", "ALFA SUSPENSA", "ALFA EXPRESS", "ALFA RETORNO", "ALFA NOVA" ],
      nomes(page)
    assert_equal 5, page.total_count
    assert_equal({ todas: 5, alta: 2, baixa: 3 }, page.variation_counts)
    assert_equal [ 1, EstablishmentListingQuery::DEFAULT_PER_PAGE ], [ page.page, page.per_page ]
    assert_nil page.overall_totals
  end

  # O pedido do usuário (10/09/2026): dois ECs do mesmo CNPJ são um cliente e uma linha, com
  # o faturamento somado. Os valores esperados saem das lojas declaradas, não de números
  # fixados aqui — é a soma que precisa estar certa, não um total memorizado.
  test "ECs do mesmo CNPJ viram uma linha só, somando o faturamento" do
    page = com_irmao

    linha = cliente(page, "11222333000181")
    principal, irmao = lojas.first, loja_irma

    assert_equal 5, page.rows.size, "o EC irmão não abre linha nova"
    assert_equal 5, page.total_count, "a paginação conta clientes"
    assert_equal 2, linha["ec_count"].to_i
    assert_equal principal.total_m1 + irmao.total_m1, linha["previous_full_revenue"].to_d
    assert_equal principal.total_atual + irmao.total_atual, linha["current_revenue"].to_d
    assert_equal 300 + irmao.total_m1, linha["previous_revenue"].to_d,
      "o mês anterior comparável soma os dois ECs dentro da faixa de dias"
  end

  # A asserção que impede o erro mais caro desta mudança. Todo filtro da tela nasceu por EC;
  # se um deles voltar para o WHERE antes do GROUP BY, o cliente com dois ECs em que só um
  # casa aparece com a soma de um EC — faturamento errado e calado. Buscar pelo número de um
  # EC tem que devolver o cliente inteiro.
  test "filtrar por um EC não recorta a soma do cliente" do
    inteiro = cliente(com_irmao, "11222333000181")

    [ "30000001", "30000006" ].each do |ec|
      recorte = listing(query: ec)

      assert_equal 1, recorte.rows.size, "buscar #{ec} devolve um cliente"
      assert_equal 2, recorte.rows.first["ec_count"].to_i
      REVENUE_COLUMNS.each do |column|
        assert_equal inteiro[column].to_d, recorte.rows.first[column].to_d,
          "#{column} ao buscar pelo EC #{ec} tem que somar os dois ECs"
      end
    end
  end

  # Somar por EC e somar por cliente dão o mesmo dinheiro: o agrupamento muda a contagem de
  # linhas, nunca o total. É o que garante que os cards da primeira dobra não se mexeram.
  test "agrupar por CNPJ não altera nenhum total em dinheiro" do
    page = com_irmao
    todas = lojas.select { |loja| loja.sub_channel_name == ALFA } + [ loja_irma ]

    assert_equal todas.sum(&:total_m1), page.totals[:previous_full_revenue]
    assert_equal todas.sum(&:total_atual), page.totals[:current_revenue]
    REVENUE_COLUMNS.each do |column|
      assert_equal page.rows.sum { |row| row[column].to_d }, page.totals.fetch(column.to_sym)
    end
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
  #
  # Agora a regra aparece na própria linha, e não só na contagem: o filtro de status compara
  # o valor agregado, então quem filtra "suspensos" nunca recebe uma linha escrita "Ativo".
  test "CNPJ com um EC ativo e outro suspenso é um cliente ativo, na linha e no filtro" do
    page = com_irmao(contract_status: "Suspended")
    counts = page.status_counts

    assert_equal 4, counts["Active"], "o CNPJ com um EC ativo continua ativo"
    assert_equal 1, counts["Suspended"], "só a ALFA SUSPENSA tem todos os ECs suspensos"
    assert_equal "Active", cliente(page, "11222333000181")["contract_status"]
    assert_equal [ "ALFA SUSPENSA" ], nomes(listing(statuses: [ "Suspended" ])),
      "o cliente de status misto não entra no filtro de suspensos"
  end

  # A data do último acesso ao app entra nas datas do ciclo. Não é enfeite: a view
  # audit_accreditation_earnings condiciona o prêmio de entrada a ter havido acesso ao app,
  # então a tela precisa deixar ver quem acessou e quando.
  #
  # A asserção é contra a data literal da planilha de propósito: a planilha traz horário de
  # Brasília e a coluna o guarda sem converter, então só a leitura crua devolve o dia certo.
  # Ver o comentário na view do subcanal.
  test "traz a data de uso do app do cliente" do
    linhas = por_nome(listing)

    assert_equal Date.new(2026, 8, 20), linhas["ALFA LANCHES"]["last_app_access_at"].to_date
    assert_nil linhas["ALFA EXPRESS"]["last_app_access_at"], "cliente sem acesso não inventa data"
  end

  # Com dois ECs, o cliente entrou na data mais antiga e usou o app na mais recente: um EC
  # novo não rejuvenesce o credenciamento de quem já era cliente.
  test "datas do ciclo do cliente: entrou na mais antiga, usou o app na mais recente" do
    linha = cliente(com_irmao(app_access_at: "2026-08-25 09:00"), "11222333000181")

    assert_equal Date.new(2026, 8, 25), linha["last_app_access_at"].to_date
    assert_equal Date.new(2026, 2, 1), linha["accredited_on"].to_date
  end

  # Pedido do usuário (10/09/2026): na coluna do EC fica só o Net MDR, e só quando é
  # porcentagem positiva. Dos 470 ECs da carteira real, 253 chegam "Inativo", 4 negativos e
  # 2 zerados — nenhum desses afirma alíquota nenhuma, e mostrá-los sugeria faixa de
  # remuneração que o valor não tem.
  test "o Net MDR chega só quando é porcentagem positiva" do
    linhas = por_nome(listing)

    assert_equal "0.4211".to_d, linhas["ALFA LANCHES"]["net_mdr_min"]
    assert_equal "0.4211".to_d, linhas["ALFA LANCHES"]["net_mdr_max"]
    assert_nil linhas["ALFA EXPRESS"]["net_mdr_min"], "\"Inativo\" não é porcentagem"
    assert_nil linhas["ALFA SUSPENSA"]["net_mdr_min"], "zero não é porcentagem positiva"
    assert_nil linhas["ALFA RETORNO"]["net_mdr_min"], "negativo não é porcentagem positiva"
    assert_nil linhas["ALFA NOVA"]["net_mdr_min"], "EC fora do Mapa não inventa alíquota"
  end

  # Cinco CNPJs da carteira real têm dois Net MDR positivos diferentes entre os ECs, e num
  # deles a diferença vai de 0,62% a 2,53%. Escolher um esconderia quatro vezes a diferença:
  # chegam os dois extremos, e a tela mostra a faixa.
  test "cliente com dois Net MDR positivos diferentes traz os dois extremos" do
    linha = cliente(com_irmao(net_mdr: 0.9125), "11222333000181")

    assert_equal "0.4211".to_d, linha["net_mdr_min"]
    assert_equal "0.9125".to_d, linha["net_mdr_max"]
  end

  # O nome do cliente é o mais frequente entre os ECs, não o primeiro nem o maior: na carteira
  # real 3 CNPJs têm razão social divergente entre os ECs e 2 têm nome fantasia. MAX pegaria o
  # maior alfabeticamente — foi assim que a Clover Capital trocou razão social por nome
  # fantasia antes de passar a usar mode().
  test "o nome do cliente é o mais frequente entre os ECs" do
    extras = [
      loja("30000006", "11222333000181", "ALFA LANCHES", dias_m1: { 1 => 10 }, dias_atual: { 1 => 20 }),
      loja("30000007", "11222333000181", "ALFA OUTRO NOME", dias_m1: { 1 => 5 }, dias_atual: { 1 => 5 })
    ]
    import_synthetic_workbook(lojas: lojas + extras, filename: "BIN_TESTE_20260812.xlsx")

    linha = cliente(listing, "11222333000181")

    assert_equal 3, linha["ec_count"].to_i
    assert_equal "ALFA LANCHES", linha["trade_name"]
    assert_equal "ALFA LANCHES LTDA", linha["legal_name"]
  end

  # A melhor conversa é texto livre do Mapa e é de cada EC — 116 dos 302 clientes da carteira
  # têm mais de um texto diferente. Vão todos, rotulados pelo EC; escolher um a esmo
  # esconderia a pendência do outro ponto de venda. Quem não tem texto chega nulo, e é o
  # nulo que desabilita o botão da linha.
  test "traz a melhor conversa de cada EC do cliente, rotulada pelo EC" do
    page = com_irmao(melhor_conversa: "Verificar se tem outras máquinas")

    conversas = JSON.parse(cliente(page, "11222333000181")["best_conversations"])

    assert_equal %w[30000001 30000006], conversas.map { |item| item["ec"] }
    assert_equal "Ofereça a antecipação > Revise o MDR", conversas.first["text"]
    assert_equal "Verificar se tem outras máquinas", conversas.last["text"]
    assert_nil por_nome(page)["ALFA EXPRESS"]["best_conversations"]
  end

  # Conversa só com espaço em branco não é conversa: a coluna chega crua da planilha — o
  # importador guarda row["MELHOR CONVERSA"] sem normalizar —, e a tela antiga fazia strip
  # antes de decidir. Sem o BTRIM na consulta, o botão habilitaria para abrir um modal vazio.
  test "conversa só com espaço em branco não chega como conversa" do
    page = com_irmao(melhor_conversa: "   ")

    conversas = JSON.parse(cliente(page, "11222333000181")["best_conversations"])

    assert_equal %w[30000001], conversas.map { |item| item["ec"] },
      "o EC com texto só de espaço não entra na lista"
  end

  # A busca alcança o texto da melhor conversa: é por ele que se procura quem tem a mesma
  # pendência comercial, e o vocabulário do Mapa é fechado — 9 ações distintas na carteira.
  #
  # Sem acento também acha, e isso não é luxo: os 418 textos do lote mais recente têm acento,
  # os 418. Quem digitasse "antecipacao" não encontraria nada.
  test "busca pelo texto da melhor conversa, com ou sem acento" do
    %w[antecipação antecipacao ANTECIPAÇÃO].each do |termo|
      assert_equal [ "ALFA LANCHES" ], nomes(listing(query: termo)),
        "buscar por #{termo.inspect} precisa achar quem tem a conversa"
    end

    # Termo que só existe na conversa de um não pode arrastar os outros junto.
    assert_empty listing(query: "reciprocidade").rows
  end

  # A anotação entra pelo CNPJ, num LEFT JOIN — e um JOIN novo numa consulta com GROUP BY é
  # exatamente onde uma linha se duplica sem ninguém perceber. O teste fixa as duas metades:
  # a anotação chega, e a contagem e os totais continuam os mesmos.
  test "a anotação do cliente chega na linha, sem duplicar nem alterar totais" do
    antes = listing

    Operations::SaveCompanyNote.call(cnpj: "11222333000181", body: "<div>Dono viaja.</div>")
    depois = listing

    assert_equal antes.rows.size, depois.rows.size
    assert_equal antes.total_count, depois.total_count
    assert_equal antes.totals, depois.totals

    linha = cliente(depois, "11222333000181")
    assert_predicate linha["company_uuid"], :present?, "a linha precisa endereçar o cliente"
    assert_predicate linha["note_id"], :present?
    assert_nil por_nome(depois)["ALFA EXPRESS"]["note_id"],
      "cliente sem anotação não herda a do vizinho"
  end

  # As três colunas de valor podem ordenar a listagem; o CNPJ é o critério de desempate,
  # senão a paginação embaralha linhas de mesmo valor entre páginas.
  test "ordena pelas colunas de valor, nos dois sentidos" do
    por_atual = nomes(listing(sort: "current_revenue", direction: "desc"))
    assert_equal [ "ALFA LANCHES", "ALFA RETORNO", "ALFA NOVA", "ALFA EXPRESS", "ALFA SUSPENSA" ],
      por_atual

    # Os cinco valores são distintos, então crescente é a lista invertida.
    assert_equal por_atual.reverse, nomes(listing(sort: "current_revenue", direction: "asc"))

    # Mês anterior cheio: 1.000 (ALFA LANCHES), 400 (SUSPENSA), 50 (EXPRESS) e dois zerados,
    # que caem no fim desempatados por CNPJ.
    assert_equal [ "ALFA LANCHES", "ALFA SUSPENSA", "ALFA EXPRESS", "ALFA RETORNO", "ALFA NOVA" ],
      nomes(listing(sort: "previous_full_revenue", direction: "desc"))
  end

  test "coluna desconhecida ou sentido inválido caem na ordem padrão" do
    padrao = nomes(listing)

    assert_equal padrao, nomes(listing(sort: "cnpj; DROP TABLE"))
    assert_equal padrao, nomes(listing(sort: nil, direction: "desc"))
    # Sentido inválido com coluna válida vale como desc, que é o primeiro clique na tela.
    assert_equal nomes(listing(sort: "current_revenue", direction: "desc")),
      nomes(listing(sort: "current_revenue", direction: "seja lá o que for"))
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
    row = por_nome(listing)["ALFA LANCHES"]
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
    assert_equal [ "ALFA LANCHES", "ALFA NOVA" ], nomes(listing(variation: "alta"))
    # Ordem padrão dentro da aba: 400 (SUSPENSA), 50 (EXPRESS) e o zerado (RETORNO).
    assert_equal [ "ALFA SUSPENSA", "ALFA EXPRESS", "ALFA RETORNO" ], nomes(listing(variation: "baixa"))
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
    assert_equal [ "ALFA EXPRESS", "ALFA RETORNO" ], nomes(segunda)
    assert_equal [ 2, 2, 3 ], [ segunda.page, segunda.per_page, segunda.total_pages ]

    alem = listing(page: 99, per_page: 2)
    assert_equal [ 3, [ "ALFA NOVA" ] ], [ alem.page, nomes(alem) ]

    assert_equal EstablishmentListingQuery::DEFAULT_PER_PAGE, listing(per_page: 0).per_page
    assert_equal EstablishmentListingQuery::PER_PAGE_OPTIONS.max, listing(per_page: 1000).per_page
  end

  test "filtra por status do contrato" do
    page = listing(statuses: [ "Suspended", "" ])

    assert_equal [ "ALFA SUSPENSA" ], nomes(page)
    assert_equal({ todas: 1, alta: 0, baixa: 1 }, page.variation_counts)
  end

  test "filtra por intervalo de datas, aceita intervalo invertido e vale para os três tipos sem marcação" do
    ativadas = listing(date_kinds: [ "ativacao" ], from_date: "2026-08-01", to_date: "2026-08-31")
    assert_equal [ "ALFA NOVA" ], nomes(ativadas)

    invertido = listing(date_kinds: [ "ativacao" ], from_date: "2026-08-31", to_date: "2026-08-01")
    assert_equal [ "ALFA NOVA" ], nomes(invertido)

    # Sem tipo marcado o intervalo vale para credenciamento, ativação ou suspensão; todos
    # foram credenciados em fevereiro, então todos entram.
    fevereiro = listing(from_date: "2026-02-01", to_date: "2026-02-28")
    assert_equal 5, fevereiro.total_count

    assert_equal 5, listing(from_date: "2026-08-01").total_count, "só um lado do intervalo não filtra"
  end

  test "busca por EC, CNPJ formatado e nome, sem distinguir maiúsculas" do
    { "30000003" => "EC", "33.444.555/0001-30" => "CNPJ formatado", "alfa suspensa" => "nome" }
      .each do |query, kind|
      assert_equal [ "ALFA SUSPENSA" ], nomes(listing(query:)), "por #{kind}"
    end
    assert_equal 0, listing(query: "zzz").total_count
  end

  test "janela mais curta recorta os dois meses" do
    row = por_nome(listing(window: window(to_day: 2)))["ALFA LANCHES"]

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

  # Pedido do usuário (14/09/2026, virou filtro em 15/09): quantos clientes ficaram até o teto
  # em cada competência. São duas contagens independentes — o mesmo cliente pode estar nas
  # duas — e o "até" inclui o próprio valor, como se lê em português.
  test "conta os clientes até o teto em cada competência, incluindo quem fica nele" do
    teto = EstablishmentListingQuery::LOW_REVENUE_REFERENCE
    # ALFA LANCHES passa o teto nas duas competências; ALFA SUSPENSA fica exatamente nele no
    # mês anterior cheio, e o "até" o inclui.
    acima_do_corte("11222333000181", previous: teto + 1, current: teto + 1)
    acima_do_corte("33444555000130", previous: teto, current: 0)

    page = listing

    assert_equal 4, page.low_revenue_counts[:previous_full],
      "dos cinco clientes, um passou do teto e o que ficou exatamente nele conta"
    assert_equal 4, page.low_revenue_counts[:current]
  end

  test "as contagens seguem o recorte, como as de status" do
    acima_do_corte("11222333000181", previous: 99_999, current: 99_999)

    assert_equal 1, listing(query: "ALFA EXPRESS").low_revenue_counts[:previous_full],
      "a busca recorta a contagem"
    assert_equal 0, listing(query: "ALFA LANCHES").low_revenue_counts[:previous_full],
      "e o cliente acima do teto não entra em recorte nenhum"
    assert_equal 1, listing(statuses: [ "Suspended" ]).low_revenue_counts[:previous_full],
      "o filtro de status também vale"
  end

  # Quem decide se o teto filtra — e por qual competência — é a base escolhida no dropdown
  # (decisão do usuário, 15/09/2026). Com "mês atual", quem faturou muito no mês passado e
  # nada agora aparece; com "mês anterior cheio", o contrário.
  test "o teto filtra pela competência que a base escolhe" do
    acima_do_corte("11222333000181", previous: 20_000, current: 20_000)
    acima_do_corte("22333444000105", previous: 25_000, current: 2_000)
    acima_do_corte("33444555000130", previous: 1_000, current: 26_000)

    atual = listing(max_revenue: 5_000, revenue_basis: "atual").rows.map { |row| row["cnpj"] }

    assert_includes atual, "22333444000105", "cabe pelo mês atual, mesmo com o anterior acima"
    assert_not_includes atual, "11222333000181", "acima do teto no mês atual"
    assert_not_includes atual, "33444555000130",
      "o mês anterior cheio baixo não salva quem está acima do teto no mês atual"
    assert_equal 3, listing(max_revenue: 5_000, revenue_basis: "atual").total_count

    anterior = listing(max_revenue: 5_000, revenue_basis: "anterior").rows.map { |r| r["cnpj"] }

    assert_includes anterior, "33444555000130", "cabe pelo mês anterior cheio, com 1.000"
    assert_not_includes anterior, "22333444000105", "25.000 no mês anterior cheio"
    assert_equal 3, listing(max_revenue: 5_000, revenue_basis: "anterior").total_count
  end

  # "Todas" é o estado desligado: o teto viaja na URL e não filtra nada. É o jeito explícito
  # de voltar à tela sem filtro, no lugar da regra implícita que o topo da escala carregava.
  test "sem base escolhida o teto não filtra, mesmo viajando na URL" do
    acima_do_corte("11222333000181", previous: 99_999, current: 99_999)

    assert_equal 5, listing(max_revenue: 1_000).total_count
    assert_equal 5, listing(max_revenue: 1_000, revenue_basis: "").total_count
    assert_equal 5, listing(max_revenue: 1_000, revenue_basis: "todas").total_count,
      "qualquer valor fora da lista fechada é o estado desligado"
    assert_equal 4, listing(max_revenue: 1_000, revenue_basis: "atual").total_count,
      "e com base escolhida o mesmo teto filtra: sai o que tem 99.999 no mês atual"
  end

  # O topo da escala voltou a significar o próprio valor: quem liga e desliga o filtro é a
  # base. Acima do topo o valor é preso à escala, e não vira ausência de teto.
  test "o teto é preso à escala e ao passo do slider" do
    teto = EstablishmentListingQuery::LOW_REVENUE_THRESHOLD

    assert_equal teto, EstablishmentListingQuery.normalize_max_revenue(teto + 50_000)
    assert_equal 0, EstablishmentListingQuery.normalize_max_revenue(-500)
    assert_equal 12_000, EstablishmentListingQuery.normalize_max_revenue(12_400),
      "o valor cai no passo de baixo, como a alça faz"
    assert_nil EstablishmentListingQuery.normalize_max_revenue("")
    assert_nil EstablishmentListingQuery.normalize_max_revenue(nil)
  end

  # Zero é escolha, e não ausência dela (pedido do usuário, 15/09/2026): teto zero responde
  # "quem não faturou nada no mês atual".
  test "teto zero mostra quem não faturou nada no mês atual" do
    cnpjs = listing(max_revenue: 0, revenue_basis: "atual").rows.map { |row| row["cnpj"] }

    assert_equal [ "33444555000130" ], cnpjs,
      "só ALFA SUSPENSA está zerada no mês atual; os outros quatro venderam alguma coisa"
    assert_equal 0, EstablishmentListingQuery.normalize_max_revenue(0),
      "zero atravessa a normalização como escolha"
    assert_nil EstablishmentListingQuery.normalize_max_revenue("")
  end

  # Com teto escolhido, o bloco conta dentro do resultado — e pela referência quando não há
  # escolha, que não é o topo da escala.
  test "as contagens do bloco usam o teto escolhido" do
    acima_do_corte("11222333000181", previous: 20_000, current: 1_000)

    page = listing(max_revenue: 5_000, revenue_basis: "atual")

    assert_equal 5, page.total_count, "ALFA LANCHES entra pelo mês atual, com 1.000"
    assert_equal 4, page.low_revenue_counts[:previous_full],
      "mas no mês anterior cheio ele tem 20.000 e fica de fora da contagem"
    assert_equal 5, page.low_revenue_counts[:current]
    assert_equal 5_000, page.low_revenue_counts[:ceiling]

    # Desligado, a contagem volta à referência — e o bloco anuncia a mesma faixa que contou.
    sem_filtro = listing(max_revenue: 5_000)

    assert_equal EstablishmentListingQuery::LOW_REVENUE_REFERENCE,
      sem_filtro.low_revenue_counts[:ceiling]
  end

  # A segunda alça (pedido do usuário, 15/09/2026): a faixa corta pelas duas pontas, e quem
  # fica abaixo do piso sai da lista tanto quanto quem passa do teto.
  test "a faixa filtra pelas duas pontas" do
    acima_do_corte("11222333000181", previous: 1_000, current: 3_000)
    acima_do_corte("22333444000105", previous: 1_000, current: 12_000)
    acima_do_corte("33444555000130", previous: 1_000, current: 30_000)

    page = listing(min_revenue: 10_000, max_revenue: 20_000, revenue_basis: "atual")

    assert_equal [ "22333444000105" ], page.rows.map { |row| row["cnpj"] },
      "3.000 fica abaixo do piso e 30.000 passa do teto; só o 12.000 está na faixa"
    assert_equal 1, page.total_count
    assert_equal 4, listing(max_revenue: 20_000, revenue_basis: "atual").total_count,
      "sem piso, quem fatura pouco volta para a lista"
  end

  # Alças trocadas entram em ordem, como o intervalo de datas já fazia. A tela e a consulta
  # chamam a mesma normalização de propósito: se só uma delas ordenasse, o painel anunciaria
  # uma faixa e a tabela listaria outra.
  test "as alças trocadas entram em ordem" do
    assert_equal [ 1_000, 5_000 ], EstablishmentListingQuery.normalize_revenue_bounds(5_000, 1_000)
    assert_equal [ 1_000, 5_000 ], EstablishmentListingQuery.normalize_revenue_bounds(1_000, 5_000)
    assert_equal [ nil, 5_000 ], EstablishmentListingQuery.normalize_revenue_bounds("", 5_000)
    assert_equal [ 0, 5_000 ], EstablishmentListingQuery.normalize_revenue_bounds(0, 5_000),
      "zero é piso escolhido, e não ausência de piso"

    acima_do_corte("11222333000181", previous: 1_000, current: 12_000)

    invertida = listing(min_revenue: 20_000, max_revenue: 10_000, revenue_basis: "atual")

    assert_equal [ "11222333000181" ], invertida.rows.map { |row| row["cnpj"] },
      "a faixa invertida na URL lista o mesmo que a faixa na ordem certa"
  end

  # O piso em zero é o fundo da escala e não corta: "de R$ 0,00" quer dizer "sem piso". Um
  # `>= 0` literal tiraria da lista quem fechou o mês negativo por estorno.
  test "o piso em zero não corta" do
    acima_do_corte("11222333000181", previous: -5_000, current: -5_000)

    cnpjs = listing(min_revenue: 0, max_revenue: 5_000, revenue_basis: "atual")
      .rows.map { |row| row["cnpj"] }

    assert_includes cnpjs, "11222333000181",
      "quem fechou negativo continua abaixo do teto e dentro da faixa"
  end

  # O bloco conta a mesma faixa que a tabela lista (decisão do usuário, 15/09/2026). Antes ele
  # só sabia contar até o teto e, com um piso escolhido, anunciaria um número maior que o da
  # tabela ao lado dele.
  test "as contagens do bloco respeitam o piso" do
    acima_do_corte("11222333000181", previous: 12_000, current: 12_000)
    acima_do_corte("22333444000105", previous: 2_000, current: 2_000)

    page = listing(min_revenue: 10_000, max_revenue: 20_000, revenue_basis: "atual")

    assert_equal [ 10_000, 20_000 ],
      [ page.low_revenue_counts[:floor], page.low_revenue_counts[:ceiling] ]
    assert_equal 1, page.total_count
    assert_equal 1, page.low_revenue_counts[:current],
      "o bloco conta o mesmo cliente que a tabela lista"
    assert_equal 1, page.low_revenue_counts[:previous_full]

    assert_equal 0, listing(min_revenue: 10_000, max_revenue: 20_000).low_revenue_counts[:floor],
      "desligado, o bloco volta a contar desde zero"
  end

  # A escala deixou de ser linear (pedido do usuário, 16/09/2026). O passo cresce com o valor
  # porque a carteira não se distribui pela escala: com passo fixo de R$ 1.000 a faixa que esta
  # tela audita ocupava 10% do trilho, e as duas alças se encavalavam dentro dela.
  test "as paradas do slider dão à faixa auditada a maior parte do trilho" do
    paradas = EstablishmentListingQuery::REVENUE_STOPS
    baixas = paradas.count { |valor| valor <= EstablishmentListingQuery::LOW_REVENUE_REFERENCE }

    assert_equal 0, paradas.first
    assert_equal EstablishmentListingQuery::LOW_REVENUE_THRESHOLD, paradas.last
    assert_equal paradas.sort.uniq, paradas, "as paradas sobem e não se repetem"
    assert_operator baixas.fdiv(paradas.size), :>, 0.7,
      "de 0 a R$ 30.000 tem de ocupar a maior parte do trilho"
    assert_equal EstablishmentListingQuery::LOW_REVENUE_STEP, paradas[2] - paradas[1],
      "na base da escala o passo continua sendo de R$ 1.000"
  end

  # A alça mostra a posição de uma parada; o filtro usa o valor. Se as duas regras divergirem,
  # a tela desenha uma faixa e o servidor recorta outra.
  test "valor fora das paradas cai na parada de baixo, na alça e no filtro" do
    assert_equal 40_000, EstablishmentListingQuery.normalize_max_revenue(45_500)
    assert_equal EstablishmentListingQuery::REVENUE_STOPS.index(40_000),
      EstablishmentListingQuery.revenue_stop_index(45_500)
    assert_equal EstablishmentListingQuery::REVENUE_STOPS.index(12_000),
      EstablishmentListingQuery.revenue_stop_index(12_400)
    assert_equal 0, EstablishmentListingQuery.revenue_stop_index(-500)
  end

  # Troca o faturamento consolidado do cliente para um valor acima do corte: a planilha
  # sintética trabalha em centenas, e o corte é de dezenas de milhares.
  def acima_do_corte(cnpj, previous:, current:)
    establishment = Establishment.joins(:company).find_by!(companies: { cnpj: })
    DailyRevenueConsolidated.where(establishment_id: establishment.id).delete_all
    competencias = [ [ window.previous_period, previous ], [ window.current_period, current ] ]
    competencias.each do |period, valor|
      next if valor.to_d.zero?

      DailyRevenueConsolidated.create!(
        channel_id: establishment.channel_id, establishment_id: establishment.id,
        source_import_batch: @batch, period:, day: 1, amount: valor, provisional: false
      )
    end
  end

  def listing(window: self.window, **options)
    EstablishmentListingQuery.new(
      channel_id: @batch.channel_id, sub_channel_id: @sub_channel.id, window:, **options
    ).call
  end

  def nomes(page) = page.rows.map { |row| row["trade_name"] }

  def por_nome(page) = page.rows.index_by { |row| row["trade_name"] }

  def cliente(page, cnpj) = page.rows.find { |row| row["cnpj"] == cnpj }

  # Importa um segundo lote em que o CNPJ da ALFA LANCHES ganha um EC irmão. O conteúdo muda
  # (o irmão fatura), então o SHA-256 difere do primeiro — dois imports no mesmo segundo com
  # o mesmo conteúdo seriam recusados como arquivo repetido.
  def com_irmao(**atributos)
    @irma = loja("30000006", "11222333000181", "ALFA LANCHES II",
      dias_m1: { 1 => 10 }, dias_atual: { 1 => 20 }, **atributos)
    import_synthetic_workbook(lojas: lojas + [ @irma ], filename: "BIN_TESTE_20260812.xlsx")
    listing
  end

  def loja_irma = @irma

  def window(to_day: cutoff)
    PeriodWindow.new(period: BinWorkbook::CURRENT_PERIOD, from_day: 1, to_day:, max_day: cutoff)
  end

  def cutoff
    BinWorkbook.cutoff_day(lojas)
  end

  # Cinco ECs no MIC ALFA cobrindo cada classificação das abas, e um no MIC BETA que nunca
  # pode aparecer. Os valores esperados saem destes dados, não de números fixados nos testes.
  # Os cinco Net MDR cobrem as quatro formas que a planilha real traz — positivo, "Inativo",
  # zero e negativo — mais o EC sem valor nenhum.
  def lojas
    @lojas ||= [
      loja("30000001", "11222333000181", "ALFA LANCHES", dias_m1: { 1 => 100, 2 => 200, 25 => 700 },
        dias_atual: { 1 => 150, 2 => 50, 10 => 300 }, proposta: true,
        app_access_at: "2026-08-20 14:30", net_mdr: 0.4211,
        melhor_conversa: "Ofereça a antecipação > Revise o MDR"),
      loja("30000002", "22333444000105", "ALFA EXPRESS", dias_m1: { 1 => 50 },
        dias_atual: { 1 => 10, 2 => 20 }, net_mdr: "Inativo"),
      loja("30000003", "33444555000130", "ALFA SUSPENSA", contract_status: "Suspended",
        dias_m1: { 1 => 400 }, dias_atual: {}, net_mdr: 0),
      loja("30000004", "44555666000172", "ALFA RETORNO", dias_m1: {}, dias_atual: { 5 => 80 },
        net_mdr: -0.31),
      loja("30000005", "55666777000109", "ALFA NOVA", dias_m1: {}, dias_atual: { 3 => 60 }),
      loja("40000001", "66777888000156", "BETA CAFE", sub_channel_name: "MIC BETA",
        dias_m1: { 1 => 900 }, dias_atual: { 1 => 900 })
    ]
  end

  def loja(ec, cnpj, trade_name, sub_channel_name: ALFA, contract_status: "Active", proposta: false,
    app_access_at: nil, melhor_conversa: nil, net_mdr: nil, dias_m1:, dias_atual:)
    BinWorkbook::Loja.new(
      ec:, cnpj:, sub_channel_name:, legal_name: "#{trade_name} LTDA", trade_name:,
      contract_status:, dias_m1:, dias_atual:, proposta:, app_access_at:, melhor_conversa:, net_mdr:
    )
  end
end
