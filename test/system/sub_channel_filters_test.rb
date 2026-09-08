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

    # O calendário abre no mês corrente; o intervalo de agosto exige voltar um mês.
    click_button "Mês anterior"
    assert_selector ".datepicker__month", text: /agosto/i

    find("#date_range_panel button[data-day='5']").click
    find("#date_range_panel button[data-day='9']").click
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

    # Abre no M0 da janela aplicada — junho, o padrão com volume nos três meses.
    assert_selector ".datepicker__month", text: /junho de 2026/i
    click_button "Ano anterior"
    assert_selector ".datepicker__month", text: /junho de 2025/i
    click_button "Próximo ano"
    assert_selector ".datepicker__month", text: /junho de 2026/i

    # Maio a junho: o usuário escolhe, mesmo maio não tendo volume importado.
    click_button "Mês anterior"
    find("#date_range_panel button[data-day='9']").click
    click_button "Próximo mês"
    find("#date_range_panel button[data-day='20']").click
    click_button "Concluir"
    click_button "Aplicar"

    assert_current_path(/from_date=2026-05-09/)
    assert_selector "p", text: /Exibindo\s+Maio a junho de 2026/i
  end
end
