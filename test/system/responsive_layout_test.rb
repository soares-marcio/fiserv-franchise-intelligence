require "application_system_test_case"

class ResponsiveLayoutTest < ApplicationSystemTestCase
  setup do
    import_synthetic_workbook
    refresh_audit_views
  end

  test "telas principais não criam overflow entre 320 e 1400 pixels" do
    paths = [
      reports_path,
      stalled_reports_path,
      weekly_reports_path,
      three_months_reports_path,
      recurring_reports_path,
      indicators_reports_path,
      establishments_path,
      import_batches_path,
      users_path,
      audit_events_path
    ]

    paths.each do |path|
      visit path
      VIEWPORTS.each_key do |viewport|
        with_viewport(viewport) { assert_page_fits_viewport(label: "#{path} em #{viewport}") }
      end
    end
  end

  test "menu móvel confina a página e fecha por Escape e pelo backdrop" do
    visit reports_path

    with_viewport(:modern_phone) do
      click_button "Abrir ou fechar o menu"

      assert_selector "#primary_nav.is-open", visible: true
      assert_selector "#main-content[inert]"
      assert_selector ".nav-backdrop", visible: true
      assert_selector "#primary_nav a:focus"

      find("body").send_keys(:escape)
      assert_no_selector "#primary_nav.is-open"
      assert_no_selector "#main-content[inert]"
      assert_selector "button[aria-controls='primary_nav']:focus"

      click_button "Abrir ou fechar o menu"
      page.driver.browser.action.move_to_location(12, 350).click.perform
      assert_no_selector "#primary_nav.is-open"

      click_button "Abrir ou fechar o menu"
      page.driver.browser.manage.window.resize_to(*VIEWPORTS.fetch(:desktop))
      assert_no_selector "#primary_nav.is-open"
      assert_no_selector "#main-content[inert]"
    end
  end

  test "controles essenciais respeitam alvos de toque no telefone" do
    sub_channel = SubChannel.active.first
    visit sub_channel_report_path(sub_channel)

    with_viewport(:modern_phone) do
      assert_touch_targets(
        ".nav-toggle, .search-content, .nav-link, .btn, .filter-pill__trigger, " \
        ".filter-pill--select, .datepicker__nav-btn"
      )
    end
  end

  test "calendário semanal vira lista móvel sem perder o detalhamento do dia" do
    visit weekly_reports_path

    with_viewport(:modern_phone) do
      assert_selector ".mobile-calendar-list", visible: true
      assert_no_selector ".revenue-calendar", visible: true

      first(".mobile-calendar-day[href]").click
      assert_selector "dialog[open] turbo-frame#day_companies", wait: 10
    end
  end

  test "listagem do MIC vira cartões e os filtros continuam recolhíveis" do
    sub_channel = SubChannel.active.first
    visit sub_channel_report_path(sub_channel)

    with_viewport(:modern_phone) do
      assert_selector ".mobile-establishment-list", visible: true
      assert_no_selector ".establishment-revenue-table", visible: true

      find(".mobile-filter-disclosure > summary").click
      assert_no_selector "#status_filter_trigger", visible: true
      find(".mobile-filter-disclosure > summary").click
      assert_selector "#status_filter_trigger", visible: true

      find(".mobile-filter-disclosure > summary").click
      assert_no_selector "#status_filter_trigger", visible: true
      page.driver.browser.manage.window.resize_to(*VIEWPORTS.fetch(:desktop_edge))
      assert_selector "#status_filter_trigger", visible: true
    end
  end

  test "listagens operacionais usam cartões apenas no telefone" do
    visit import_batches_path

    with_viewport(:modern_phone) do
      assert_selector ".responsive-card-table td[data-label='Arquivo']", visible: true
      assert_no_selector ".responsive-card-table thead", visible: true
      assert_page_fits_viewport
    end

    with_viewport(:desktop) do
      assert_selector ".responsive-card-table thead", visible: true
    end
  end

  test "telas da plataforma mantêm ações e metadados dentro do telefone" do
    platform = platform_admin_user
    member = create_user(email: "mobile@exemplo.com",
      created_by: User.find_by!(email_address: "chefe@exemplo.com"))
    click_button "Sair"
    sign_in_through_ui(platform)

    visit platform_organization_path(default_organization)
    with_viewport(:modern_phone) do
      assert_page_fits_viewport
      assert_touch_targets(".support-actions .btn")
      assert_selector "a[href='#{platform_user_path(member)}']"
    end

    visit platform_user_path(member)
    with_viewport(:modern_phone) { assert_page_fits_viewport }
  end

  # No iPad deitado (1194px) os dez itens do menu quebravam em duas linhas e o cabeçalho
  # tomava quase metade da altura antes do primeiro número (09/10/2026): até 1199px o menu
  # fica recolhido no botão, como no telefone.
  test "tablet deitado recolhe o menu numa linha só e abre pelo botão" do
    visit reports_path

    [ :desktop_edge, :tablet_landscape ].each do |viewport|
      with_viewport(viewport) do
        assert_no_selector "#primary_nav", visible: true
        click_button "Abrir ou fechar o menu"
        assert_selector "#primary_nav.is-open", visible: true
        assert_selector "#primary_nav a", text: "Histórico", visible: true
        find("body").send_keys(:escape)
        assert_no_selector "#primary_nav.is-open"
        assert_page_fits_viewport
      end
    end
  end

  test "desktop preserva menu horizontal sem backdrop" do
    visit reports_path

    with_viewport(:desktop) do
      assert_selector "#primary_nav", visible: true
      assert_no_selector ".nav-toggle", visible: true
      assert_no_selector ".nav-backdrop", visible: true
      assert_page_fits_viewport
    end
  end

  # As tabelas quebram texto em qualquer ponto para nome longo não estourar a coluna, e o
  # selo herdava a regra: no iPad deitado, "Ativo" virava "Ativ" e "o", com o "o" fora da
  # pílula (09/10/2026). Selo é rótulo curto e fica numa linha só.
  test "selos das tabelas ficam numa linha só no tablet deitado" do
    visit establishments_path

    with_viewport(:tablet_landscape) do
      lines = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll(".table .badge")).map((badge) => {
          const range = document.createRange()
          range.selectNodeContents(badge)
          return range.getClientRects().length
        })
      JS

      assert lines.any?, "a tela precisa ter selos para o teste valer"
      assert lines.all? { |count| count == 1 }, "selo quebrado em mais de uma linha: #{lines.inspect}"
    end
  end
end
