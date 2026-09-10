require "application_system_test_case"

# Os dois filtros da tela de subcanal são JavaScript escrito à mão (352 linhas entre o
# datepicker e o multiselect) e até aqui nada os exercitava: o que se prova abaixo é que a
# escolha do usuário chega à URL, que é o contrato com o servidor.
class SubChannelFiltersTest < ApplicationSystemTestCase
  setup do
    import_synthetic_workbook
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

  # O EC abre os lançamentos diários num <dialog> nativo, com o conteúdo carregado por
  # Turbo Frame. O que se prova aqui é o caminho inteiro: clique, diálogo aberto, tabela
  # preenchida e fechamento.
  test "clicar no EC abre o modal de lançamentos diários" do
    visit sub_channel_report_path(@sub_channel)

    assert_no_selector "dialog.daily-modal[open]"
    # Clique na célula do CNPJ, longe do link do EC: é a linha que abre, não o link.
    find("tr.daily-row", text: "30000001").all("td")[1].click

    assert_selector "dialog.daily-modal[open]"
    within "dialog.daily-modal" do
      assert_selector "h2", text: "EC 30000001"
      assert_selector "tbody th", text: "01"
      assert_selector "td", text: /150,00/
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
    find("tr.daily-row", text: "30000001").all("td")[1].click
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

  # O modal da melhor conversa monta a sequência no navegador, a partir do texto que o botão
  # carrega. Sem teste de sistema nada disso é exercitado: o servidor entrega o botão certo
  # mesmo que o JavaScript nunca rode.
  test "o botão da melhor conversa abre o modal com a sequência de ações" do
    visit sub_channel_report_path(@sub_channel)

    assert_no_selector "dialog[open]"
    abrir_acoes("30000001").find("button.conversation-trigger").click

    # O modal se identifica pelo mesmo nome da célula do estabelecimento: o fantasia.
    assert_selector "dialog[open] h3.table-title", text: "ALFA LANCHES"
    # "Ligar > Enviar proposta" vira dois passos: o separador é o da planilha.
    assert_selector "dialog[open] .conversation-steps li", count: 2
    assert_selector "dialog[open] .conversation-steps li", text: "Ligar"
    assert_selector "dialog[open] .conversation-steps li", text: "Enviar proposta"

    # A linha inteira abre os lançamentos diários; o clique no botão não pode disparar os dois.
    assert_selector "dialog[open]", count: 1
    assert_no_selector "dialog[open] turbo-frame#daily_revenues"
  end

  # Quem não tem texto no Mapa não tem o que abrir, e o botão precisa dizer isso antes do
  # clique — desabilitado de verdade, não só sem ação.
  test "sem melhor conversa no Mapa o botão vem desabilitado" do
    visit sub_channel_report_path(@sub_channel)

    botao = abrir_acoes("90000001").find("button.conversation-trigger")

    assert botao.disabled?, "o botão da linha sem conversa precisa vir desabilitado"
  end

  # No hover, a célula de variação assume a cor da própria variação — verde para alta,
  # vermelho para queda. A cor vem do chip que está dentro, então o teste passa o mouse e
  # compara o fundo das duas linhas.
  test "a coluna de variação muda de cor no hover conforme a variação" do
    visit sub_channel_report_path(@sub_channel)

    fundo = lambda do |ec|
      linha = find("tr.daily-row", text: ec)
      page.driver.browser.action.move_to(linha.native).perform
      page.evaluate_script(<<~JS)
        (() => {
          const linha = [...document.querySelectorAll("tr.daily-row")]
            .find((tr) => tr.textContent.includes("#{ec}"))
          return getComputedStyle(linha.querySelector("td.variation-col")).backgroundColor
        })()
      JS
    end

    alta = fundo.call("30000001")
    queda = fundo.call("90000001")

    assert_not_equal alta, queda, "alta e queda precisam ter fundos diferentes no hover"
  end

  private

  # As ações da linha ficam num menu fechado; devolve a linha com ele aberto.
  def abrir_acoes(ec)
    linha = find("tr.daily-row", text: ec)
    linha.find("summary.actions-menu__trigger").click
    linha
  end
end
