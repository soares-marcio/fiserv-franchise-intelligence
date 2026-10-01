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
    @shared_cnpj = "11222333000181"
    @channel_a = Channel.find_by!(name: BinWorkbook::CHANNEL)

    @org_b = Organization.create!(name: "Organização B")
    import_synthetic_workbook(organization: @org_b, stores: stores_of_b, filename: "BIN_B_20260812.xlsx",
      channel: "MASTER DA ORGANIZACAO B", report_id: "8888")
    @channel_b = Channel.find_by!(name: "MASTER DA ORGANIZACAO B")
    @admin_a = admin_user(email: "admin-a@exemplo.com")
    @admin_b = create_user(email: "admin-b@exemplo.com", organization: @org_b, organization_admin: true)
  end

  test "o administrador de A não vê B em tela nenhuma, nem por URL" do
    sign_in_as(@admin_a)

    [ reports_path, stalled_reports_path, weekly_reports_path, three_months_reports_path,
      recurring_reports_path, indicators_reports_path, establishments_path ].each do |screen|
      get screen
      assert_response :success, screen
      assert_no_match(/ORGANIZACAO B|MIC BRAVO|BRAVO/, response.body, "#{screen} mostra a organização B")
    end

    get reports_path(channel_id: @channel_b.uuid)
    assert_response :not_found
    get sub_channel_report_path(SubChannel.find_by!(channel: @channel_b))
    assert_response :not_found
    get establishment_path(Establishment.find_by!(ec: "70000001"))
    assert_response :not_found
  end

  test "o mesmo CNPJ nas duas organizações: a ficha e a busca de A só mostram os ECs de A" do
    sign_in_as(@admin_a)
    company = Company.find_by!(cnpj: @shared_cnpj)

    get establishment_path(company)
    assert_response :success
    assert_match(/30000001/, response.body)
    assert_no_match(/70000001|ORGANIZACAO B/, response.body)

    get search_path(q: @shared_cnpj)
    assert_no_match(/70000001|MIC BRAVO/, response.body)
  end

  test "a anotação do mesmo CNPJ é uma por organização, e editar em A não toca a de B" do
    note_b = Operations::SaveCompanyNote.call(organization: @org_b, cnpj: @shared_cnpj,
      body: "<div>Segredo de B</div>", author: @admin_b)
    company = Company.find_by!(cnpj: @shared_cnpj)
    sign_in_as(@admin_a)

    get edit_company_note_path(company)
    assert_response :success
    assert_no_match(/Segredo de B/, response.body)

    patch company_note_path(company), params: { body: "<div>Leitura de A</div>" }

    assert_equal 2, CompanyNote.where(cnpj: @shared_cnpj).count
    assert_equal "Segredo de B", note_b.reload.body.to_plain_text
    assert_equal "Leitura de A", CompanyNote.find_by!(organization: default_organization, cnpj: @shared_cnpj).body.to_plain_text

    # O selo "anotado" da listagem também é por organização: B anotou, A ainda não.
    CompanyNote.find_by!(organization: default_organization, cnpj: @shared_cnpj).destroy
    get establishments_path
    assert_select ".note-trigger__dot", count: 0
  end

  test "o administrador de B não vê a carteira de A nem alcança os usuários de A" do
    sign_in_as(@admin_b)

    get reports_path
    assert_response :success
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}|MIC ALFA/, response.body)

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
  def stores_of_b
    model = BinWorkbook.default_stores.first
    [
      model.class.new(**model.to_h.merge(ec: "70000001", cnpj: @shared_cnpj, sub_channel_name: "MIC BRAVO",
        legal_name: "MESMO CLIENTE EM B LTDA", trade_name: "BRAVO CAFE")),
      model.class.new(**model.to_h.merge(ec: "70000002", cnpj: "99888777000166", sub_channel_name: "MIC BRAVO",
        legal_name: "SO DE B LTDA", trade_name: "BRAVO BAR"))
    ]
  end
end
