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

  # Recorte por MIC: dois MICs do mesmo Master, e o ator só tem um. Tela a tela, porque o
  # recorte por Master já valia em todas e o por MIC não: a de indicadores mostrava os dez
  # MICs do Master a quem tinha um só (homologação de 29/09/2026).
  test "o ator de um MIC não vê o MIC vizinho do mesmo Master em nenhuma tela" do
    user = scoped_user(permissions: [ Permission::REPORTS_READ, Permission::ESTABLISHMENTS_READ ],
      sub_channel: @mic_alfa)
    sign_in_as(user)

    [ reports_path, stalled_reports_path, weekly_reports_path, three_months_reports_path,
      recurring_reports_path, indicators_reports_path ].each do |tela|
      get tela
      assert_response :success, tela
      assert_no_match(/MIC BETA/, response.body, "#{tela} mostra o MIC vizinho")
    end
    assert_match(/MIC ALFA/, response.body)

    get establishments_path
    assert_no_match(/BETA CAFE/, response.body, "a listagem de clientes mostra EC do MIC vizinho")

    get search_path(q: "BETA")
    assert_no_match(/BETA CAFE|MIC BETA/, response.body, "a busca encontra o MIC vizinho")
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

  # A listagem de clientes e a busca eram os dois caminhos que ainda atravessavam a carteira
  # inteira: a busca, em especial, é o atalho mais curto até um dado — digitar um CNPJ
  # revelaria em que Master ele está e o nome do MIC junto.
  test "a listagem de clientes mostra só os do escopo, inclusive na contagem" do
    entra_no_canal(@canal_a)

    get establishments_path

    assert_response :success
    assert_no_match(/OMEGA/, response.body)
    assert_no_match(/99888777000166/, response.body)
  end

  test "a busca não encontra EC de outro Master, nem por CNPJ exato" do
    entra_no_canal(@canal_a)

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
    entra_no_canal(@canal_a)

    get search_path(q: "30000001")

    assert_match(/30000001/, response.body)
  end

  # Redirecionar confirmaria que aquele EC existe e a que cliente pertence; 404 não conta
  # nada. É a mesma escolha do MIC de outro Master.
  test "EC de outro Master responde 404 em vez de redirecionar para a ficha" do
    entra_no_canal(@canal_a)
    de_fora = Establishment.find_by!(ec: "70000001")

    get establishment_path(de_fora)

    assert_response :not_found
  end

  test "a ficha do cliente não mistura ECs de Masters diferentes" do
    # O mesmo CNPJ com EC nos dois Masters é o caso que obriga o recorte dentro da ficha.
    company = Establishment.find_by!(ec: "30000001").company
    outro_ec = Establishment.create!(ec: "70000009", company:, channel: @canal_b)
    entra_no_canal(@canal_a)

    get establishment_path(company)

    assert_response :success
    assert_no_match(/70000009/, response.body)
    assert_match(/30000001/, response.body)
    assert_not_nil outro_ec.reload
  end

  # A anotação é presa ao CNPJ e não tem canal: a regra tem de vir do domínio — vê quem tem
  # ao menos um EC daquele CNPJ no próprio escopo.
  test "anotação de cliente de outro Master não é vista nem editada" do
    de_fora = Establishment.find_by!(ec: "70000001").company
    Operations::SaveCompanyNote.call(organization: default_organization, cnpj: de_fora.cnpj, body: "<div>Segredo do outro Master</div>")
    # Com a permissão de anotação, mas sem o cliente no escopo: é o recorte que precisa
    # negar aqui, e não a falta de chave — por isso 404, e não 403.
    sign_in_as(scoped_user(permissions: [ Permission::NOTES_READ, Permission::NOTES_WRITE ],
      channel: @canal_a, email: "tem-chave@exemplo.com"))

    get edit_company_note_path(de_fora)
    assert_response :not_found

    patch company_note_path(de_fora), params: { body: "<div>invasão</div>" }
    assert_response :not_found
    assert_match(/Segredo/, CompanyNote.find_by(cnpj: de_fora.cnpj).body.to_plain_text)
  end

  test "a anotação do próprio escopo continua acessível, e grava quem editou" do
    company = Establishment.find_by!(ec: "30000001").company
    user = scoped_user(permissions: [ Permission::NOTES_READ, Permission::NOTES_WRITE ],
      channel: @canal_a, email: "anota@exemplo.com")
    sign_in_as(user)

    patch company_note_path(company), params: { body: "<div>Ligar amanhã</div>" }

    nota = CompanyNote.find_by(cnpj: company.cnpj)
    assert_equal "Ligar amanhã", nota.body.to_plain_text
    assert_equal user, nota.author, "a anotação passa a saber quem escreveu"
  end

  # O selo de "tem anotação" aparece em listagem, busca e modal: se ele não fosse recortado,
  # contaria que o cliente do outro Master tem anotação — e que ele existe.
  test "o selo de anotação não aparece para cliente fora do escopo" do
    de_fora = Establishment.find_by!(ec: "70000001").company
    Operations::SaveCompanyNote.call(organization: default_organization, cnpj: de_fora.cnpj, body: "<div>Nota alheia</div>")
    entra_no_canal(@canal_a)

    get establishments_path

    assert_no_match(/Nota alheia/, response.body)
    assert_no_match(/#{de_fora.cnpj}/, response.body)
  end

  # Cache é a falha mais silenciosa possível: dois escopos com a mesma chave serviriam um ao
  # outro sem erro nenhum.
  test "escopos diferentes não compartilham cache" do
    a = ReportScope.new(scope: escopo_do_canal(@canal_a.id))
    b = ReportScope.new(scope: escopo_do_canal(@canal_b.id))

    assert_not_equal a.scope.cache_key, b.scope.cache_key
    assert_not_equal escopo_da_organizacao.cache_key, a.scope.cache_key
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
