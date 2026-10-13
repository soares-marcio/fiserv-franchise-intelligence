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
    sign_out_through_ui
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

  # O botão ficava no meio da barra, entre o logo e a busca, e a gaveta abria colada na
  # borda direita, longe do toque que a abriu (10/10/2026). Ele é o último controle da
  # linha, no HTML também, para a ordem do Tab seguir a da tela.
  test "botão do menu fica na ponta direita, colado na gaveta que abre" do
    visit reports_path

    [ :modern_phone, :tablet, :tablet_landscape ].each do |viewport|
      with_viewport(viewport) do
        assert page.evaluate_script(<<~JS), "#{viewport}: algum controle passa à direita do botão"
          (() => {
            const toggle = document.querySelector(".nav-toggle").getBoundingClientRect();
            return [...document.querySelectorAll(".topbar-tools a, .topbar-tools button")]
              .map((el) => el.getBoundingClientRect())
              .filter((r) => r.width > 0 && r.top < toggle.bottom && r.bottom > toggle.top)
              .every((r) => r.right <= toggle.right + 0.5);
          })()
        JS
        assert page.evaluate_script(
          "document.querySelector('.topbar-tools').lastElementChild.matches('.nav-toggle')"
        ), "#{viewport}: o botão não é o último da barra no HTML"

        click_button "Abrir ou fechar o menu"
        assert_selector "#primary_nav.is-open", visible: true
        assert page.evaluate_script(<<~JS), "#{viewport}: a gaveta não abre do lado do botão"
          (() => {
            const toggle = document.querySelector(".nav-toggle").getBoundingClientRect();
            const nav = document.querySelector("#primary_nav").getBoundingClientRect();
            const center = toggle.left + toggle.width / 2;
            return center >= nav.left && center <= nav.right;
          })()
        JS
        find("body").send_keys(:escape)
        assert_no_selector "#primary_nav.is-open"
      end
    end
  end

  # O nome, a organização e um "Sair" sem caixa ficavam soltos no canto da barra
  # (10/10/2026). No desktop viram o menu da conta; com o menu recolhido, vão para a gaveta:
  # quem está agindo no topo dela, e o "Sair" separado, no fim.
  test "no desktop a conta abre num menu, com e-mail e Sair, e fecha por Escape e clique fora" do
    visit reports_path

    with_viewport(:desktop) do
      trigger = find(".account-menu__trigger", text: "Teste")
      assert_text default_organization.name
      assert_no_button "Sair"

      trigger.click
      assert_selector ".account-menu__panel", text: "chefe@exemplo.com", visible: true
      assert_button "Sair"
      find("body").send_keys(:escape)
      assert_no_button "Sair"
      assert_selector ".account-menu__trigger:focus"

      trigger.click
      find("h1").click
      assert_no_button "Sair"

      trigger.click
      click_button "Sair"
      assert_current_path new_session_path
    end
  end

  # Com dez itens o menu quebrava em duas linhas a 1280px (11/10/2026). Acessos e Histórico
  # são administração, usados por quem administra: no desktop moram no menu da conta, como
  # as configurações no GitHub e no Google, e a barra fica com os relatórios e a carteira.
  test "no desktop a administração fica no menu da conta e o menu cabe numa linha" do
    visit reports_path

    with_viewport(:desktop) do
      assert_no_selector "#primary_nav a", text: "Acessos", visible: true
      assert_no_selector "#primary_nav a", text: "Histórico", visible: true
      tops = page.evaluate_script(<<~JS)
        [...document.querySelectorAll("#primary_nav a.nav-link")]
          .filter((link) => link.getBoundingClientRect().width > 0)
          .map((link) => Math.round(link.getBoundingClientRect().top))
      JS
      assert_equal 1, tops.uniq.size, "o menu quebrou em #{tops.uniq.size} linhas"

      find(".account-menu__trigger").click
      within ".account-menu__panel" do
        assert_text(/administração/i)
        assert_link "Acessos", href: users_path
        assert_link "Histórico", href: audit_events_path
      end
      click_link "Acessos"
      assert_current_path users_path
    end
  end

  test "com o menu recolhido, a conta fica na gaveta: quem age no topo e o Sair no fim" do
    visit reports_path

    [ :modern_phone, :tablet_landscape ].each do |viewport|
      with_viewport(viewport) do
        assert_no_selector ".account-menu", visible: true
        assert_no_button "Sair"

        click_button "Abrir ou fechar o menu"
        within "#primary_nav" do
          assert_selector ".nav-account", text: "Teste", visible: true
          assert_selector ".nav-account", text: default_organization.name
          assert_selector ".nav-account", text: "chefe@exemplo.com"
          assert_selector ".nav-admin", text: /administração/i, visible: true
          assert_selector ".nav-admin a", text: "Acessos", visible: true
          assert_selector ".nav-admin a", text: "Histórico", visible: true
          assert_button "Sair"
        end
        assert page.evaluate_script(
          "(n => n.scrollWidth <= n.clientWidth)(document.querySelector('#primary_nav'))"
        ), "#{viewport}: a gaveta transborda para o lado"
        assert page.evaluate_script(<<~JS), "#{viewport}: a conta não abre a gaveta nem o Sair a fecha"
          (() => {
            const nav = document.querySelector("#primary_nav");
            const links = nav.querySelectorAll("a.nav-link");
            const account = nav.querySelector(".nav-account");
            const exit = nav.querySelector(".nav-account-exit");
            return nav.firstElementChild === account && nav.lastElementChild === exit &&
              account.getBoundingClientRect().bottom <= links[0].getBoundingClientRect().top &&
              exit.getBoundingClientRect().top >= links[links.length - 1].getBoundingClientRect().bottom;
          })()
        JS
        find("body").send_keys(:escape)
      end
    end
  end

  # A busca era um quadrado arredondado, o selo uma pílula e o "Sair" não tinha caixa: três
  # formas lado a lado (10/10/2026). Os controles do topo têm a mesma altura e o mesmo canto.
  test "controles do topo têm a mesma altura e o mesmo arredondamento" do
    visit reports_path

    [ :desktop, :tablet_landscape, :modern_phone ].each do |viewport|
      with_viewport(viewport) do
        boxes = page.evaluate_script(<<~JS)
          [".search-content", ".header-status", ".account-menu__trigger", ".nav-toggle"]
            .map((selector) => document.querySelector(selector))
            .filter((el) => el && el.getBoundingClientRect().width > 0)
            .map((el) => [el.className, Math.round(el.getBoundingClientRect().height),
              getComputedStyle(el).borderTopLeftRadius, getComputedStyle(el).borderTopWidth])
        JS
        assert_operator boxes.size, :>=, 3, "#{viewport}: #{boxes.inspect}"
        assert_equal 1, boxes.map(&:second).uniq.size, "#{viewport}: alturas diferentes #{boxes.inspect}"
        assert_equal 1, boxes.map(&:third).uniq.size, "#{viewport}: cantos diferentes #{boxes.inspect}"
        assert_equal [ "1px" ], boxes.map(&:fourth).uniq, "#{viewport}: controle sem caixa #{boxes.inspect}"
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

  # Com nomes do tamanho dos reais, o cabeçalho da tabela do MIC passava 9px da tela no iPad
  # deitado (balões de ajuda invisíveis na borda e contagens que não quebravam). O Safari do
  # iPad reduz a página que transborda, a largura enxergada pelo CSS passa de 1200px e o menu
  # horizontal voltava só nesta tela (10/10/2026).
  test "o MIC com nomes longos não transborda no tablet deitado e mantém o menu recolhido" do
    stores = (1..12).map do |index|
      BinWorkbook::Store.new(
        ec: "5#{index.to_s.rjust(7, '0')}", cnpj: "1#{index.to_s.rjust(13, '0')}",
        sub_channel_name: "MIC ELCIO EUSTAQUIO AGUAS LINDAS GO",
        legal_name: "MARCA HIGIENE COMERCIO E ATACADISTA DE PRODUTOS DE LIMPEZA LTDA #{index}",
        trade_name: "SUPERBOM SUPERMERCADO E PADARIA #{index}", contract_status: "Active",
        previous_days: { 1 => 1_234_567, 10 => 98_765 }, current_days: { 1 => 2_345_678, 14 => 87_654 }
      )
    end
    import_synthetic_workbook(stores:, channel: "MASTER FRANQUEADO REGIAO GOIAS", report_id: "7777",
      filename: "BIN_LONGO_20260812.xlsx")
    refresh_audit_views
    visit sub_channel_report_path(SubChannel.find_by!(name: "MIC ELCIO EUSTAQUIO AGUAS LINDAS GO"))

    with_viewport(:tablet_landscape) do
      assert_page_fits_viewport
      assert_no_selector "#primary_nav", visible: true
    end
  end
end
