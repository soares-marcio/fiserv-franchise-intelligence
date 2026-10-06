require "test_helper"

# Uma chave por item do menu de relatórios: quem concede marca o link que a pessoa vai ver,
# e ela vê exatamente esse — nem um a mais, que era o caso da chave única "Ver relatórios"
# (homologação de 06/10/2026). As telas de detalhe vão com o item de onde se chega a elas.
class ReportMenuPermissionsTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    import_synthetic_workbook
    @channel = Channel.find_by!(name: BinWorkbook::CHANNEL)
    @mic = SubChannel.find_by!(name: "MIC ALFA", channel: @channel)
  end

  test "cada item abre só as próprias telas, e o menu mostra só ele" do
    screens.each_with_index do |(key, paths), index|
      sign_in_as(scoped_user(permissions: [ key ], channel: @channel, email: "item#{index}@exemplo.com"))

      paths.each do |path|
        get path
        assert_response :success, "#{key} deveria abrir #{path}"
      end
      (screens.keys - [ key ]).each do |other|
        get screens[other].first
        assert_response :forbidden, "#{key} não deveria abrir #{screens[other].first}"
      end
      get establishments_path
      assert_response :forbidden, "#{key} não abre Estabelecimentos"

      report_links = css_select("nav.primary-nav a").map { |link| link["href"] } & menu_paths
      assert_equal [ paths.first ], report_links, "o menu de #{key} mostra outro item"

      sign_out
      travel 31.seconds
    end
  end

  test "sem o Faturamento, a raiz leva ao primeiro item que a pessoa tem" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_RECURRING ], channel: @channel))

    get root_path

    assert_redirected_to recurring_reports_path
  end

  test "sem relatório nenhum, a raiz leva a Estabelecimentos" do
    sign_in_as(scoped_user(permissions: [ Permission::ESTABLISHMENTS_READ ], channel: @channel))

    get root_path

    assert_redirected_to establishments_path
  end

  test "sem o Faturamento, o nome do MIC nos cards não vira link para um 403" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_RECURRING, Permission::REPORTS_INDICATORS ],
      channel: @channel))

    [ recurring_reports_path, indicators_reports_path ].each do |path|
      get path
      assert_response :success
      assert_select "a[href=?]", sub_channel_report_path(@mic), count: 0
      assert_match "MIC ALFA", response.body
    end
  end

  test "baixar vale na tela que a pessoa tem, e só nela" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_THREE_MONTHS, Permission::REPORTS_EXPORT ],
      channel: @channel))

    get three_months_reports_path(format: :csv)
    assert_response :success
    get recurring_reports_path(format: :csv)
    assert_response :forbidden
  end

  private

  def screens
    {
      Permission::REPORTS_REVENUE => [ reports_path, sub_channel_report_path(@mic) ],
      Permission::REPORTS_CLOVER => [ stalled_reports_path ],
      Permission::REPORTS_WEEKLY => [ weekly_reports_path ],
      Permission::REPORTS_THREE_MONTHS => [ three_months_reports_path, three_months_sub_channel_report_path(@mic) ],
      Permission::REPORTS_RECURRING => [ recurring_reports_path ],
      Permission::REPORTS_INDICATORS => [ indicators_reports_path ]
    }
  end

  def menu_paths
    screens.values.map(&:first)
  end
end
