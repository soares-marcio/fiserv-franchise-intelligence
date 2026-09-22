require "test_helper"

# O que esta fase existe para impedir: um ator ver dado de carteira que não é dele. Os
# testes acima já garantem que ele **pode** abrir a tela; estes garantem que a tela, aberta,
# mostra só o que lhe cabe.
class DataScopeTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    # Duas carteiras completas, importadas de verdade: o recorte tem de valer sobre o mesmo
    # caminho que a tela usa, não sobre dado montado à mão.
    import_synthetic_workbook
    @canal_a = Channel.find_by!(name: BinWorkbook::CANAL)
    @mic_alfa = SubChannel.find_by!(name: "MIC ALFA", channel: @canal_a)
    @mic_beta = SubChannel.find_by!(name: "MIC BETA", channel: @canal_a)

    import_synthetic_workbook(lojas: outras_lojas, filename: "BIN_OUTRO_20260812.xlsx",
      canal: "MASTER FRANQUEADO OUTRO", report_id: "8888")
    @canal_b = Channel.find_by!(name: "MASTER FRANQUEADO OUTRO")
    refresh_audit_views
  end

  test "o ator de um Master não vê o outro em nenhuma tela" do
    entra_no_canal(@canal_a)

    get reports_path
    assert_response :success
    assert_select "body" do
      assert_select "*", text: /MASTER FRANQUEADO OUTRO/, count: 0
    end

    get recurring_reports_path
    assert_no_match(/OUTRO/, response.body)

    get indicators_reports_path
    assert_no_match(/MIC OMEGA/, response.body)
  end

  # O seletor de canal é uma lista de Masters: oferecer um que o ator não pode abrir conta
  # que ele existe.
  test "o seletor de canal mostra só os Masters do escopo" do
    entra_no_canal(@canal_a)

    get reports_path

    assert_match(/#{Regexp.escape(@canal_a.name)}/, response.body)
    assert_no_match(/#{Regexp.escape(@canal_b.name)}/, response.body)
  end

  # Canal de outro Master na URL não pode virar "sem filtro" nem responder 403 com o nome —
  # 404 é o que o portal já fazia para MIC de outro Master, e a regra continua a mesma.
  test "canal de outro Master na URL responde 404" do
    entra_no_canal(@canal_a)

    get reports_path(channel_id: @canal_b.uuid)

    assert_response :not_found
  end

  test "MIC de fora do escopo responde 404, inclusive nos modais" do
    entra_no_canal(@canal_a)
    mic_de_fora = SubChannel.find_by!(channel: @canal_b)

    get sub_channel_report_path(mic_de_fora)
    assert_response :not_found

    get three_months_sub_channel_report_path(mic_de_fora)
    assert_response :not_found
  end

  # Recorte por MIC: dois MICs do mesmo Master, e o ator só tem um.
  test "o ator de um MIC não vê o MIC vizinho do mesmo Master" do
    user = scoped_user(permissions: [ Permission::REPORTS_READ ], sub_channel: @mic_alfa)
    sign_in_as(user)

    get reports_path

    assert_response :success
    assert_match(/MIC ALFA/, response.body)
    assert_no_match(/MIC BETA/, response.body)
  end

  test "o ator de um MIC não abre a tela do MIC vizinho" do
    user = scoped_user(permissions: [ Permission::REPORTS_READ ], sub_channel: @mic_alfa)
    sign_in_as(user)

    get sub_channel_report_path(@mic_beta)

    assert_response :not_found
  end

  # A exportação é o caminho mais perigoso: leva o recorte inteiro num arquivo. Se o recorte
  # falhar ali, a carteira alheia sai em CSV sem ninguém notar.
  test "a exportação respeita o recorte" do
    user = scoped_user(permissions: [ Permission::REPORTS_READ, Permission::REPORTS_EXPORT ],
      channel: @canal_a)
    sign_in_as(user)

    get recurring_reports_path(format: :csv)

    assert_response :success
    assert_no_match(/OUTRO/, response.body)
  end

  # Cache é a falha mais silenciosa possível: dois escopos com a mesma chave serviriam um ao
  # outro sem erro nenhum.
  test "escopos diferentes não compartilham cache" do
    a = ReportScope.new(scope: escopo_do_canal(@canal_a.id))
    b = ReportScope.new(scope: escopo_do_canal(@canal_b.id))

    assert_not_equal a.scope.cache_key, b.scope.cache_key
    assert_not_equal AccessScope.everything.cache_key, a.scope.cache_key
    assert_not_equal a.totals, b.totals
  end

  test "escopo vazio não enxerga nada — e não vira a carteira inteira" do
    vazio = AccessScope.new(full_channel_ids: [], sub_channel_ids: [])

    assert_empty ReportScope.new(scope: vazio).revenue_by_sub_channel
    assert_empty Establishment.in_scope(vazio)
  end

  private

  def entra_no_canal(channel)
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_READ, Permission::ESTABLISHMENTS_READ ],
      channel: channel))
  end

  def outras_lojas
    [
      BinWorkbook::Loja.new(
        ec: "70000001", cnpj: "99888777000166", sub_channel_name: "MIC OMEGA",
        legal_name: "OMEGA COMERCIO LTDA", trade_name: "OMEGA",
        contract_status: "Active", dias_m1: { 1 => 500 }, dias_atual: { 1 => 900 }
      )
    ]
  end
end
