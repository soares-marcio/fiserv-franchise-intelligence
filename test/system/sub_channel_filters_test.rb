require "application_system_test_case"

# Os dois filtros da tela de subcanal são JavaScript escrito à mão (352 linhas entre o
# datepicker e o multiselect) e até aqui nada os exercitava: o que se prova abaixo é que a
# escolha do usuário chega à URL, que é o contrato com o servidor.
class SubChannelFiltersTest < ApplicationSystemTestCase
  # A planilha padrão põe os dois ECs do MIC ALFA no mesmo CNPJ, e desde que a listagem agrupa
  # por cliente eles são uma linha só — o MIC ficaria com uma linha, sem com que comparar. Daí
  # os dois acréscimos: um terceiro EC do mesmo cliente, com conversa própria (é o caso que o
  # modal novo tem de mostrar: 116 dos 302 clientes da carteira têm mais de um texto), e um
  # segundo cliente em queda, sem conversa nenhuma.
  CNPJ_ALFA = "11.222.333/0001-81".freeze
  CNPJ_PARADA = "77.888.999/0001-44".freeze

  setup do
    terceiro_ec = BinWorkbook::Loja.new(
      ec: "90000002", cnpj: "11222333000181", sub_channel_name: "MIC ALFA",
      legal_name: "ALFA COMERCIO DE ALIMENTOS LTDA", trade_name: "ALFA LANCHES",
      contract_status: "Active", dias_m1: { 1 => 5 }, dias_atual: { 1 => 40 },
      melhor_conversa: "Verificar outras máquinas > Revisar MDR", proposta: false
    )
    em_queda = BinWorkbook::Loja.new(
      ec: "30000009", cnpj: "77888999000144", sub_channel_name: "MIC ALFA",
      legal_name: "ALFA PARADA LTDA", trade_name: "ALFA PARADA",
      contract_status: "Active", dias_m1: { 1 => 500 }, dias_atual: {},
      melhor_conversa: nil, proposta: false
    )
    import_synthetic_workbook(lojas: BinWorkbook.default_lojas + [ terceiro_ec, em_queda ])
    refresh_audit_views
    @sub_channel = SubChannel.find_by!(name: "MIC ALFA")
  end

  test "escolhe um intervalo no calendário e o filtro chega na URL" do
    visit sub_channel_report_path(@sub_channel)

    find("#date_range_trigger").click
    assert_selector "#date_range_panel", visible: true

    # O calendário do subcanal abre no mês corrente; um passo atrás traz agosto, e
    # setembro fica ao lado.
    click_button "Mês anterior"
    assert_selector ".datepicker__month", text: /agosto de 2026/i
    assert_selector ".datepicker__month", text: /setembro de 2026/i

    find("#date_range_panel button[data-date='2026-08-05']").click
    find("#date_range_panel button[data-date='2026-08-09']").click
    click_button "Concluir"

    assert_no_selector "#date_range_panel", visible: true
    assert_selector "#date_range_trigger", text: "05/08/2026 a 09/08/2026"

    click_button "Filtrar"

    # assert_current_path espera a navegação terminar; current_url leria a URL anterior.
    assert_current_path(/from_date=2026-08-05/, url: true)
    assert_current_path(/to_date=2026-08-09/, url: true)
  end

  test "marca dois tipos de data, remove um pelo chip e envia só o que sobrou" do
    visit sub_channel_report_path(@sub_channel)

    find("#date_kind_filter_trigger").click
    assert_selector "#date_kind_filter_menu", visible: true

    check "Credenciamento"
    check "Ativação"

    within "#date_kind_filter_trigger" do
      assert_selector ".status-tag", count: 2
    end

    click_button "Remover Credenciamento"

    within "#date_kind_filter_trigger" do
      assert_selector ".status-tag", count: 1
      assert_selector ".status-tag", text: "Ativação"
    end
    assert_not find("#date_kind_credenciamento", visible: :all).checked?

    click_button "Filtrar"

    assert_current_path(/date_kind%5B%5D=ativacao/, url: true)
    assert_no_current_path(/credenciamento/, url: true)
  end

  # A linha do cliente abre os lançamentos diários num <dialog> nativo, com o conteúdo
  # carregado por Turbo Frame. O que se prova aqui é o caminho inteiro: clique, diálogo
  # aberto, tabela preenchida com a soma dos ECs do CNPJ, e fechamento.
  test "clicar na linha abre o modal de lançamentos diários do cliente" do
    visit sub_channel_report_path(@sub_channel)

    assert_no_selector "dialog.daily-modal[open]"
    # Clique na célula do Net MDR, longe do link do nome: é a linha que abre, não o link.
    find("tr.daily-row", text: CNPJ_ALFA).all("td").first.click

    assert_selector "dialog.daily-modal[open]"
    within "dialog.daily-modal" do
      assert_selector "h2", text: "ALFA LANCHES"
      assert_selector ".page-description", text: /soma de 3 ECs/
      assert_selector "tbody th", text: "01"
      # O dia 1 do cliente é a soma dos três ECs: 150 + 10 + 40.
      assert_selector "td", text: /200,00/
      click_button "Fechar lançamentos diários"
    end

    assert_no_selector "dialog.daily-modal[open]"
  end

  # O 3M passou a escolher a janela por calendário, com navegação de mês e de ano. O que
  # se prova aqui é que a escolha chega à URL e à apuração.
  test "escolhe a janela do 3M pelo calendário, navegando por ano" do
    visit three_months_reports_path

    find("#date_range_trigger").click
    assert_selector "#date_range_panel", visible: true

    # Abre no M0 da janela aplicada — junho —, com julho ao lado.
    assert_selector ".datepicker__month", text: /junho de 2026/i
    assert_selector ".datepicker__month", text: /julho de 2026/i
    click_button "Ano anterior"
    assert_selector ".datepicker__month", text: /junho de 2025/i
    click_button "Próximo ano"
    assert_selector ".datepicker__month", text: /junho de 2026/i

    # Maio a junho: o usuário escolhe, mesmo maio não tendo volume importado.
    click_button "Mês anterior"
    find("#date_range_panel button[data-date='2026-05-09']").click
    find("#date_range_panel button[data-date='2026-06-20']").click
    click_button "Concluir"
    click_button "Aplicar"

    assert_current_path(/from_date=2026-05-09/)
    assert_selector "p", text: /Exibindo\s+Maio a junho de 2026/i
  end

  # Reprodução do relato: marcar o dia inicial, navegar meses à frente e marcar o dia final
  # sem voltar ao mês inicial. O intervalo tem que valer assim mesmo.
  test "intervalo entre meses distantes vale sem voltar ao mês inicial" do
    visit three_months_reports_path

    find("#date_range_trigger").click
    2.times { click_button "Mês anterior" }
    find("#date_range_panel button[data-date='2026-04-04']").click
    assert_selector ".date-range__label", text: "04/04/2026"

    3.times { click_button "Próximo mês" }
    assert_selector ".datepicker__month", text: /julho de 2026/i
    find("#date_range_panel button[data-date='2026-07-09']").click

    # Sem voltar ao mês inicial: o rótulo já mostra o intervalo inteiro.
    assert_selector ".date-range__label", text: "04/04/2026 a 09/07/2026"
    click_button "Concluir"
    click_button "Aplicar"

    assert_current_path(/from_date=2026-04-04/)
    assert_current_path(/to_date=2026-07-09/)
  end

  # O modal fica dentro do .table-frame da listagem e herdava o cabeçalho fixo ancorado na
  # topbar da página: o thead parava no meio da tabela. Aqui o scrollport é a própria
  # tabela, então o cabeçalho tem que colar no topo dela ao rolar.
  test "cabeçalho da tabela do modal cola no topo ao rolar" do
    visit sub_channel_report_path(@sub_channel)
    find("tr.daily-row", text: CNPJ_ALFA).all("td").first.click
    assert_selector "dialog.daily-modal[open]"
    assert_selector "dialog.daily-modal tbody th", text: "01"

    page.execute_script("document.querySelector('dialog.daily-modal .table-scroll').scrollTop = 400")
    colado = page.evaluate_script(<<~JS)
      (() => {
        const scroll = document.querySelector("dialog.daily-modal .table-scroll")
        const th = scroll.querySelector("thead th")
        return Math.abs(th.getBoundingClientRect().top - scroll.getBoundingClientRect().top) < 2
      })()
    JS

    assert colado, "o cabeçalho da tabela precisa ficar no topo do scroll do modal"
  end

  # O modal da melhor conversa monta a sequência no navegador, a partir do que o botão carrega.
  # Sem teste de sistema nada disso é exercitado: o servidor entrega o botão certo mesmo que o
  # JavaScript nunca rode. E a conversa é de cada EC — o cliente com três ECs tem duas, e as
  # duas precisam aparecer, cada uma sob o EC de onde veio.
  test "o botão da melhor conversa abre o modal com uma sequência por EC" do
    visit sub_channel_report_path(@sub_channel)

    assert_no_selector "dialog[open]"
    abrir_acoes(CNPJ_ALFA).find("button.conversation-trigger").click

    # O modal se identifica pelo mesmo nome da célula do estabelecimento: o fantasia.
    assert_selector "dialog[open] h3.table-title", text: "ALFA LANCHES"
    # Dois ECs com texto, rotulados e em ordem de EC; o terceiro não tem conversa.
    assert_selector "dialog[open] .conversation-groups__ec", count: 2
    assert_equal [ "EC 30000001", "EC 90000002" ],
      all("dialog[open] .conversation-groups__ec").map(&:text)
    # Cada texto vira dois passos: o separador ">" é o da planilha.
    assert_selector "dialog[open] .conversation-steps", count: 2
    assert_selector "dialog[open] .conversation-steps li", count: 4
    assert_selector "dialog[open] .conversation-steps li", text: "Ligar"
    assert_selector "dialog[open] .conversation-steps li", text: "Enviar proposta"
    assert_selector "dialog[open] .conversation-steps li", text: "Verificar outras máquinas"

    # A linha inteira abre os lançamentos diários; o clique no botão não pode disparar os dois.
    assert_selector "dialog[open]", count: 1
    assert_no_selector "dialog[open] turbo-frame#daily_revenues"
  end

  # Cliente sem texto em nenhum EC não tem o que abrir, e o botão precisa dizer isso antes do
  # clique — desabilitado de verdade, não só sem ação.
  test "sem melhor conversa no Mapa o botão vem desabilitado" do
    visit sub_channel_report_path(@sub_channel)

    botao = abrir_acoes(CNPJ_PARADA).find("button.conversation-trigger")

    assert botao.disabled?, "o botão da linha sem conversa precisa vir desabilitado"
  end

  # O menu de ações abre para fora da tabela, e a tabela o recortava: `.table-scroll` tem
  # `overflow-x: auto` para rolar na horizontal, e overflow declarado num eixo torna o outro
  # `auto` também. Medido na tela real, no menu da última linha: dos 100px do painel, 57
  # ficavam fora do recorte, e o resto aparecia por baixo da barra de paginação.
  #
  # A correção é o painel virar `position: fixed`, que escapa de qualquer recorte por
  # overflow — e é isso que o teste tranca. Se o controller sumir, o painel volta a
  # `absolute` e esta asserção cai. As outras duas garantem que a posição calculada aqui
  # continua colada no gatilho e dentro da janela; `elementFromPoint` prova que o rodapé do
  # painel está à vista, e não atrás de outra coisa.
  test "o menu de ações da última linha aparece inteiro, sem a tabela cortar" do
    visit sub_channel_report_path(@sub_channel)

    all("tr.daily-row").last.find("summary.actions-menu__trigger").click
    assert_selector ".actions-menu[open] .actions-menu__list"

    medida = page.evaluate_script(<<~JS)
      (() => {
        const lista = document.querySelector(".actions-menu[open] .actions-menu__list")
        const gatilho = lista.closest(".actions-menu").querySelector("summary")
        const l = lista.getBoundingClientRect()
        const g = gatilho.getBoundingClientRect()
        const alvo = document.elementFromPoint(l.left + l.width / 2, l.bottom - 6)
        return {
          posicao: getComputedStyle(lista).position,
          desalinho: Math.round(Math.abs(l.right - g.right)),
          distanciaDoGatilho: Math.round(Math.min(Math.abs(l.top - g.bottom), Math.abs(g.top - l.bottom))),
          rodapeVisivel: lista.contains(alvo),
          naJanela: l.bottom <= window.innerHeight && l.top >= 0
        }
      })()
    JS

    assert_equal "fixed", medida["posicao"], "o painel precisa escapar do recorte da tabela"
    assert_operator medida["desalinho"], :<=, 2, "o painel fica alinhado à direita do gatilho"
    # Abre para baixo; sem espaço até o fim da janela, abre para cima. As duas contam.
    assert_operator medida["distanciaDoGatilho"], :<=, 12, "e colado a ele"
    assert medida["rodapeVisivel"], "o rodapé do painel precisa estar à vista, não atrás da tabela"
    assert medida["naJanela"], "o painel precisa caber na janela"
  end

  # No hover, a célula de variação assume a cor da própria variação — verde para alta,
  # vermelho para queda. A cor vem do chip que está dentro, então o teste passa o mouse e
  # compara o fundo das duas linhas.
  test "a coluna de variação muda de cor no hover conforme a variação" do
    visit sub_channel_report_path(@sub_channel)

    fundo = lambda do |cnpj|
      linha = find("tr.daily-row", text: cnpj)
      page.driver.browser.action.move_to(linha.native).perform
      page.evaluate_script(<<~JS)
        (() => {
          const linha = [...document.querySelectorAll("tr.daily-row")]
            .find((tr) => tr.textContent.includes("#{cnpj}"))
          return getComputedStyle(linha.querySelector("td.variation-col")).backgroundColor
        })()
      JS
    end

    alta = fundo.call(CNPJ_ALFA)
    queda = fundo.call(CNPJ_PARADA)

    assert_not_equal alta, queda, "alta e queda precisam ter fundos diferentes no hover"
  end

  private

  # As ações da linha ficam num menu fechado; devolve a linha com ele aberto. A linha é
  # localizada pelo CNPJ, que é a identidade dela desde que a listagem agrupa por cliente.
  def abrir_acoes(cnpj)
    linha = find("tr.daily-row", text: cnpj)
    linha.find("summary.actions-menu__trigger").click
    linha
  end
end
