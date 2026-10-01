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
    @channel_a = Channel.find_by!(name: BinWorkbook::CHANNEL)
    @mic_alfa = SubChannel.find_by!(name: "MIC ALFA", channel: @channel_a)
    @mic_beta = SubChannel.find_by!(name: "MIC BETA", channel: @channel_a)

    import_synthetic_workbook(stores: other_stores, filename: "BIN_OUTRO_20260812.xlsx",
      channel: "MASTER FRANQUEADO OUTRO", report_id: "8888")
    @channel_b = Channel.find_by!(name: "MASTER FRANQUEADO OUTRO")
    refresh_audit_views
  end

  # Com cache real, aquecido antes pelo administrador da organização: é o cenário de
  # produção, em que a tela já foi carregada por quem vê tudo antes de o ator de um
  # recorte abri-la. Chave de cache sem o escopo serviria o resultado dele a qualquer um.
  test "o ator de um Master não vê o outro em nenhuma tela, nem pelo cache" do
    with_real_cache do
      warm_cache_as_admin
      sign_in_to_channel(@channel_a)

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
  end

  # O seletor de canal é uma lista de Masters: oferecer um que o ator não pode abrir conta
  # que ele existe.
  test "o seletor de canal mostra só os Masters do escopo" do
    sign_in_to_channel(@channel_a)

    get reports_path

    assert_match(/#{Regexp.escape(@channel_a.name)}/, response.body)
    assert_no_match(/#{Regexp.escape(@channel_b.name)}/, response.body)
  end

  # Canal de outro Master na URL não pode virar "sem filtro" nem responder 403 com o nome —
  # 404 é o que o portal já fazia para MIC de outro Master, e a regra continua a mesma.
  test "canal de outro Master na URL responde 404" do
    sign_in_to_channel(@channel_a)

    get reports_path(channel_id: @channel_b.uuid)

    assert_response :not_found
  end

  test "MIC de fora do escopo responde 404, inclusive nos modais" do
    sign_in_to_channel(@channel_a)
    outside_mic = SubChannel.find_by!(channel: @channel_b)

    get sub_channel_report_path(outside_mic)
    assert_response :not_found

    get three_months_sub_channel_report_path(outside_mic)
    assert_response :not_found
  end

  # Recorte por MIC: dois MICs do mesmo Master, e o ator só tem um. Tela a tela, porque o
  # recorte por Master já valia em todas e o por MIC não: a de indicadores mostrava os dez
  # MICs do Master a quem tinha um só (homologação de 29/09/2026).
  test "o ator de um MIC não vê o MIC vizinho do mesmo Master em nenhuma tela, nem pelo cache" do
    with_real_cache do
      warm_cache_as_admin
      user = scoped_user(permissions: [ Permission::REPORTS_READ, Permission::ESTABLISHMENTS_READ ],
        sub_channel: @mic_alfa)
      sign_in_as(user)

      TELAS_DE_RELATORIO.each do |screen|
        get screen
        assert_response :success, screen
        assert_no_match(/MIC BETA/, response.body, "#{screen} mostra o MIC vizinho")
      end
      assert_match(/MIC ALFA/, response.body)

      get establishments_path
      assert_no_match(/BETA CAFE/, response.body, "a listagem de clientes mostra EC do MIC vizinho")

      get search_path(q: "BETA")
      assert_no_match(/BETA CAFE|MIC BETA/, response.body, "a busca encontra o MIC vizinho")
    end
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
      channel: @channel_a)
    sign_in_as(user)

    get recurring_reports_path(format: :csv)

    assert_response :success
    assert_no_match(/OUTRO/, response.body)
  end

  # A listagem de clientes e a busca eram os dois caminhos que ainda atravessavam a carteira
  # inteira: a busca, em especial, é o atalho mais curto até um dado — digitar um CNPJ
  # revelaria em que Master ele está e o nome do MIC junto.
  test "a listagem de clientes mostra só os do escopo, inclusive na contagem" do
    sign_in_to_channel(@channel_a)

    get establishments_path

    assert_response :success
    assert_no_match(/OMEGA/, response.body)
    assert_no_match(/99888777000166/, response.body)
  end

  test "a busca não encontra EC de outro Master, nem por CNPJ exato" do
    sign_in_to_channel(@channel_a)

    # O termo aparece na mensagem "Nada encontrado para …", então o que se afirma é a
    # ausência de resultado, e não a ausência do texto.
    get search_path(q: "70000001")
    assert_select "a.search-result", count: 0

    get search_path(q: "99888777000166")
    assert_select "a.search-result", count: 0

    get search_path(q: "MIC OMEGA")
    assert_no_match(/OMEGA COMERCIO/, response.body)
  end

  test "a busca continua encontrando o que é do escopo" do
    sign_in_to_channel(@channel_a)

    get search_path(q: "30000001")

    assert_match(/30000001/, response.body)
  end

  # Redirecionar confirmaria que aquele EC existe e a que cliente pertence; 404 não conta
  # nada. É a mesma escolha do MIC de outro Master.
  test "EC de outro Master responde 404 em vez de redirecionar para a ficha" do
    sign_in_to_channel(@channel_a)
    outsider = Establishment.find_by!(ec: "70000001")

    get establishment_path(outsider)

    assert_response :not_found
  end

  test "a ficha do cliente não mistura ECs de Masters diferentes" do
    # O mesmo CNPJ com EC nos dois Masters é o caso que obriga o recorte dentro da ficha.
    company = Establishment.find_by!(ec: "30000001").company
    other_ec = Establishment.create!(ec: "70000009", company:, channel: @channel_b)
    sign_in_to_channel(@channel_a)

    get establishment_path(company)

    assert_response :success
    assert_no_match(/70000009/, response.body)
    assert_match(/30000001/, response.body)
    assert_not_nil other_ec.reload
  end

  # A anotação é presa ao CNPJ e não tem canal: a regra tem de vir do domínio — vê quem tem
  # ao menos um EC daquele CNPJ no próprio escopo.
  test "anotação de cliente de outro Master não é vista nem editada" do
    outsider = Establishment.find_by!(ec: "70000001").company
    Operations::SaveCompanyNote.call(organization: default_organization, cnpj: outsider.cnpj, body: "<div>Segredo do outro Master</div>")
    # Com a permissão de anotação, mas sem o cliente no escopo: é o recorte que precisa
    # negar aqui, e não a falta de chave — por isso 404, e não 403.
    sign_in_as(scoped_user(permissions: [ Permission::ESTABLISHMENTS_READ, Permission::NOTES_READ, Permission::NOTES_WRITE ],
      channel: @channel_a, email: "tem-chave@exemplo.com"))

    get edit_company_note_path(outsider)
    assert_response :not_found

    patch company_note_path(outsider), params: { body: "<div>invasão</div>" }
    assert_response :not_found
    assert_match(/Segredo/, CompanyNote.find_by(cnpj: outsider.cnpj).body.to_plain_text)
  end

  test "a anotação do próprio escopo continua acessível, e grava quem editou" do
    company = Establishment.find_by!(ec: "30000001").company
    user = scoped_user(permissions: [ Permission::ESTABLISHMENTS_READ, Permission::NOTES_READ, Permission::NOTES_WRITE ],
      channel: @channel_a, email: "anota@exemplo.com")
    sign_in_as(user)

    patch company_note_path(company), params: { body: "<div>Ligar amanhã</div>" }

    note = CompanyNote.find_by(cnpj: company.cnpj)
    assert_equal "Ligar amanhã", note.body.to_plain_text
    assert_equal user, note.author, "a anotação passa a saber quem escreveu"
  end

  # O selo de "tem anotação" aparece em listagem, busca e modal: se ele não fosse recortado,
  # contaria que o cliente do outro Master tem anotação — e que ele existe.
  test "o selo de anotação não aparece para cliente fora do escopo" do
    outsider = Establishment.find_by!(ec: "70000001").company
    Operations::SaveCompanyNote.call(organization: default_organization, cnpj: outsider.cnpj, body: "<div>Nota alheia</div>")
    sign_in_to_channel(@channel_a)

    get establishments_path

    assert_no_match(/Nota alheia/, response.body)
    assert_no_match(/#{outsider.cnpj}/, response.body)
  end

  # Cache é a falha mais silenciosa possível: dois escopos com a mesma chave serviriam um ao
  # outro sem erro nenhum.
  # A chave de cache tem de carregar o escopo. Em 30/09/2026 a tela Ganhos 3M levava na
  # chave um canal que nunca existia (nulo): quem tinha um MIC só via o resultado de quem
  # carregara a tela antes. O cache de teste é nulo, então o teste liga um de verdade.
  test "a tela Ganhos 3M não serve a um ator o cache do recorte de outro" do
    with_real_cache do
        sign_in_as(admin_user)
        get three_months_reports_path
        assert_response :success
        assert_match(/MIC BETA/, response.body)
        sign_out

        travel 31.seconds
        user = scoped_user(permissions: [ Permission::REPORTS_READ ], sub_channel: @mic_alfa)
        sign_in_as(user)
        get three_months_reports_path
        assert_response :success
        assert_no_match(/MIC BETA/, response.body, "o cache do administrador vazou para o ator do MIC")
        assert_match(/MIC ALFA/, response.body)
    end
  end

  test "escopos diferentes não compartilham cache" do
    a = ReportScope.new(scope: channel_scope(@channel_a.id))
    b = ReportScope.new(scope: channel_scope(@channel_b.id))

    assert_not_equal a.scope.cache_key, b.scope.cache_key
    assert_not_equal organization_scope.cache_key, a.scope.cache_key
    assert_not_equal a.totals, b.totals
  end

  test "escopo vazio não enxerga nada — e não vira a carteira inteira" do
    empty_one = AccessScope.new(full_channel_ids: [], sub_channel_ids: [])

    assert_empty ReportScope.new(scope: empty_one).revenue_by_sub_channel
    assert_empty Establishment.in_scope(empty_one)
  end

  private

  TELAS_DE_RELATORIO = %w[/reports /reports/stalled /reports/weekly /reports/three_months /reports/recurring
    /reports/indicators].freeze

  # O administrador vê a organização inteira: o que ele carrega enche o cache com todos
  # os Masters e MICs. Quem entra depois só pode ver o seu.
  def warm_cache_as_admin
    sign_in_as(admin_user)
    TELAS_DE_RELATORIO.each { |screen| get(screen) && assert_response(:success, screen) }
    get establishments_path
    sign_out
    # O código do autenticador não vale duas vezes na mesma janela de 30 s.
    travel 31.seconds
  end

  def with_real_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  def sign_in_to_channel(channel)
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_READ, Permission::ESTABLISHMENTS_READ ],
      channel: channel))
  end

  def other_stores
    [
      BinWorkbook::Store.new(
        ec: "70000001", cnpj: "99888777000166", sub_channel_name: "MIC OMEGA",
        legal_name: "OMEGA COMERCIO LTDA", trade_name: "OMEGA",
        contract_status: "Active", previous_days: { 1 => 500 }, current_days: { 1 => 900 }
      )
    ]
  end
end
