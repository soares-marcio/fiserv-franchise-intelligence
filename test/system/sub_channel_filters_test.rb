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
end
