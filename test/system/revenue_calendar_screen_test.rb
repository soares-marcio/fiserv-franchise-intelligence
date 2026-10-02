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

  # O modal do dia é <dialog> nativo aberto por Stimulus, com o conteúdo vindo por Turbo
  # Frame. O que só o navegador prova: o clique abre, e o caret troca o dia **sem fechar**.
  test "clicar num dia abre o modal, e o caret anda de dia sem fechá-lo" do
    visit weekly_reports_path(period: "2026-08-01")

    find("a.calendar-box[href*='/day/1?']").click

    assert_selector "dialog[open] h2.table-title", text: "Dia 1 · sábado"
    assert_selector "dialog[open] tbody tr", text: "11222333000181"

    find("dialog[open] a[aria-label='Próximo dia']").click

    assert_selector "dialog[open] h2.table-title", text: "Dia 2 · domingo"
  end

  # As setas são links comuns, e é isso que mantém a tela navegável sem JavaScript.
  test "a seta anda uma competência sem passar pelo seletor" do
    visit weekly_reports_path

    find("a[aria-label='Competência anterior']").click

    assert_current_path(/period=2026-07-01/)
    assert_selector "h2.table-title", text: "Julho de 2026"
  end

  test "filtro, exportações e calendário permanecem contidos em três larguras" do
    visit weekly_reports_path

    assert_selector ".page-hero .metric-grid .metric-card", count: 3
    assert_selector "form.filter-bar .filter-pill--select"
    assert_selector ".export-actions .export-action", count: 2
    assert_selector ".table-toolbar__meta"

    [ 320, 768, 1400 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 900)
      measure = page.evaluate_script(<<~JS)
        (() => {
          const filtro = document.querySelector(".filter-panel").getBoundingClientRect()
          const calendario = document.querySelector(".table-scroll").getBoundingClientRect()
          const botoes = [...document.querySelectorAll(".export-actions .btn")]
          const dentro = (rect) => rect.left >= 0 && rect.right <= window.innerWidth
          return {
            pagina: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            filtro_dentro: dentro(filtro),
            calendario_dentro: dentro(calendario),
            botoes_legiveis: botoes.every((botao) => botao.scrollWidth <= botao.clientWidth)
          }
        })()
      JS

      assert_operator measure["pagina"], :<=, 0, "a página não pode transbordar em #{width}px"
      assert measure["filtro_dentro"], "o filtro precisa caber em #{width}px"
      assert measure["calendario_dentro"], "o calendário precisa ficar contido em #{width}px"
      assert measure["botoes_legiveis"], "os botões de exportação precisam manter os rótulos"
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end
end
