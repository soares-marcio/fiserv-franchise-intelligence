require "test_helper"

# O que as organizações existem para impedir: uma ver qualquer coisa da outra — inclusive
# quando as duas têm o mesmo cliente. Espelho de data_scope_test, um nível acima.
class OrganizationIsolationTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    # A: a organização padrão, com a carteira sintética. B: outra, com carteira própria em
    # que um CNPJ é o mesmo de A — o caso que obriga o recorte dentro da ficha, da busca
    # e da anotação.
    import_synthetic_workbook
    refresh_audit_views
    @cnpj_comum = "11222333000181"
    @canal_a = Channel.find_by!(name: BinWorkbook::CANAL)

    @org_b = Organization.create!(name: "Organização B")
    import_synthetic_workbook(organization: @org_b, lojas: lojas_de_b, filename: "BIN_B_20260812.xlsx",
      canal: "MASTER DA ORGANIZACAO B", report_id: "8888")
    @canal_b = Channel.find_by!(name: "MASTER DA ORGANIZACAO B")
    @admin_a = admin_user(email: "admin-a@exemplo.com")
    @admin_b = create_user(email: "admin-b@exemplo.com", organization: @org_b, organization_admin: true)
  end

  test "o administrador de A não vê B em tela nenhuma, nem por URL" do
    sign_in_as(@admin_a)

    [ reports_path, stalled_reports_path, weekly_reports_path, three_months_reports_path,
      recurring_reports_path, indicators_reports_path, establishments_path ].each do |tela|
      get tela
      assert_response :success, tela
      assert_no_match(/ORGANIZACAO B|MIC BRAVO|BRAVO/, response.body, "#{tela} mostra a organização B")
    end

    get reports_path(channel_id: @canal_b.uuid)
    assert_response :not_found
    get sub_channel_report_path(SubChannel.find_by!(channel: @canal_b))
    assert_response :not_found
    get establishment_path(Establishment.find_by!(ec: "70000001"))
    assert_response :not_found
  end

  test "o mesmo CNPJ nas duas organizações: a ficha e a busca de A só mostram os ECs de A" do
    sign_in_as(@admin_a)
    company = Company.find_by!(cnpj: @cnpj_comum)

    get establishment_path(company)
    assert_response :success
    assert_match(/30000001/, response.body)
    assert_no_match(/70000001|ORGANIZACAO B/, response.body)

    get search_path(q: @cnpj_comum)
    assert_no_match(/70000001|MIC BRAVO/, response.body)
  end

  test "a anotação do mesmo CNPJ é uma por organização, e editar em A não toca a de B" do
    nota_b = Operations::SaveCompanyNote.call(organization: @org_b, cnpj: @cnpj_comum,
      body: "<div>Segredo de B</div>", author: @admin_b)
    company = Company.find_by!(cnpj: @cnpj_comum)
    sign_in_as(@admin_a)

    get edit_company_note_path(company)
    assert_response :success
    assert_no_match(/Segredo de B/, response.body)

    patch company_note_path(company), params: { body: "<div>Leitura de A</div>" }

    assert_equal 2, CompanyNote.where(cnpj: @cnpj_comum).count
    assert_equal "Segredo de B", nota_b.reload.body.to_plain_text
    assert_equal "Leitura de A", CompanyNote.find_by!(organization: default_organization, cnpj: @cnpj_comum).body.to_plain_text

    # O selo "anotado" da listagem também é por organização: B anotou, A ainda não.
    CompanyNote.find_by!(organization: default_organization, cnpj: @cnpj_comum).destroy
    get establishments_path
    assert_select ".note-trigger__dot", count: 0
  end

  test "o administrador de B não vê a carteira de A nem alcança os usuários de A" do
    sign_in_as(@admin_b)

    get reports_path
    assert_response :success
    assert_no_match(/#{Regexp.escape(BinWorkbook::CANAL)}|MIC ALFA/, response.body)

    get users_path
    assert_no_match(/admin-a@exemplo\.com/, response.body)
    get user_path(@admin_a)
    assert_response :not_found
  end

  test "escopos de organizações diferentes nunca dividem a chave de cache" do
    assert_not_equal AccessScope.for(@admin_a).cache_key, AccessScope.for(@admin_b).cache_key
  end

  private

  # Carteira de B: ECs próprios, um deles com o CNPJ que também existe em A.
  def lojas_de_b
    modelo = BinWorkbook.default_lojas.first
    [
      modelo.class.new(**modelo.to_h.merge(ec: "70000001", cnpj: @cnpj_comum, sub_channel_name: "MIC BRAVO",
        legal_name: "MESMO CLIENTE EM B LTDA", trade_name: "BRAVO CAFE")),
      modelo.class.new(**modelo.to_h.merge(ec: "70000002", cnpj: "99888777000166", sub_channel_name: "MIC BRAVO",
        legal_name: "SO DE B LTDA", trade_name: "BRAVO BAR"))
    ]
  end
end
