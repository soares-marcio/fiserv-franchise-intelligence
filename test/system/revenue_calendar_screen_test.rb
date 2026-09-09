require "application_system_test_case"

# O calendário do ritmo perdeu o botão Aplicar: escolher a competência já é a ação. Isso é
# JavaScript, e sem teste de sistema ninguém percebe que parou de funcionar — a tela
# continuaria abrindo, só que presa no mês em que abriu.
class RevenueCalendarScreenTest < ApplicationSystemTestCase
  setup do
    import_synthetic_workbook
    refresh_audit_views
  end

  test "escolher a competência no seletor já traz o calendário do mês" do
    visit weekly_reports_path

    assert_selector "h2.table-title", text: "Agosto de 2026"

    select "julho de 2026", from: "period"

    assert_current_path(/period=2026-07-01/)
    assert_selector "h2.table-title", text: "Julho de 2026"
    # Julho de 2026 começa numa quarta: a primeira linha da grade cobre os dias 1 a 4.
    assert_selector "tbody th[scope=row]", text: "1–4"
  end

  # As setas são links comuns, e é isso que mantém a tela navegável sem JavaScript.
  test "a seta anda uma competência sem passar pelo seletor" do
    visit weekly_reports_path

    find("a[aria-label='Competência anterior']").click

    assert_current_path(/period=2026-07-01/)
    assert_selector "h2.table-title", text: "Julho de 2026"
  end
end
