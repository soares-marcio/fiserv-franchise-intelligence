require "test_helper"

# A organização nasce sem nome; o administrador dela dá o nome no primeiro acesso, depois da
# senha e do segundo fator — e antes de qualquer tela.
class OrganizationOnboardingTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @sem_nome = Organization.create!
    @admin = create_user(email: "admin@exemplo.com", organization: @sem_nome, organization_admin: true)
  end

  test "administrador de organização sem nome é levado a nomeá-la em qualquer tela" do
    sign_in_as(@admin)

    get reports_path
    assert_redirected_to edit_organization_path

    get users_path
    assert_redirected_to edit_organization_path

    get edit_organization_path
    assert_response :success
    assert_match(/Dê um nome à sua organização/, response.body)
  end

  test "nome em branco é recusado; nome válido libera o portal e fica no cabeçalho" do
    sign_in_as(@admin)

    patch organization_path, params: { name: "   " }
    assert_response :unprocessable_entity
    assert_not @sem_nome.reload.named?

    patch organization_path, params: { name: "Franquia Norte" }
    assert_redirected_to root_path
    assert_equal "Franquia Norte", @sem_nome.reload.name
    assert_equal "Franquia Norte", AuditEvent.find_by(action: "organization.named").metadata["nome"]

    get reports_path
    assert_response :success
    assert_match(/Franquia Norte/, response.body)
  end

  test "nome já usado por outra organização é recusado" do
    sign_in_as(@admin)

    patch organization_path, params: { name: default_organization.name }

    assert_response :unprocessable_entity
    assert_not @sem_nome.reload.named?
  end

  test "colaborador e plataforma não são redirecionados, nem nomeiam" do
    colaborador = scoped_user(permissions: [ Permission::REPORTS_READ ], email: "colab@exemplo.com",
      organization: @sem_nome)
    sign_in_as(colaborador)
    get reports_path
    assert_response :success
    patch organization_path, params: { name: "Tentativa" }
    assert_response :forbidden
    assert_not @sem_nome.reload.named?
    sign_out

    travel 31.seconds
    sign_in_as(platform_admin_user)
    get platform_organizations_path
    assert_response :success
    patch organization_path, params: { name: "Tentativa" }
    assert_response :forbidden
  end

  # Nomear é uma vez: depois disso a tela não abre mais por acidente.
  test "organização já nomeada não volta ao onboarding" do
    @sem_nome.update!(name: "Já Nomeada")
    sign_in_as(@admin)

    get reports_path
    assert_response :success
  end
end
