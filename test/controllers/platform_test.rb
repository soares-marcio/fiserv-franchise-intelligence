require "test_helper"

# A conta da plataforma: cria organizações e o administrador de cada uma, vê quem existe,
# presta suporte — e não lê dado de organização nenhuma.
class PlatformTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    import_synthetic_workbook
    @plataforma = platform_admin_user
    @admin_a = admin_user(email: "admin-a@exemplo.com")
    @convidado = scoped_user(permissions: [ Permission::REPORTS_READ ], channel: Channel.first,
      email: "convidado@exemplo.com", created_by: @admin_a)
  end

  test "ao entrar, a plataforma cai na tela de organizações, não em relatório" do
    sign_in_as(@plataforma)

    get root_path

    assert_redirected_to platform_organizations_path
  end

  test "a tela macro lista organizações, administradores e convidados sem nome de Master" do
    Audit.record("session.start", user: @convidado)
    sign_in_as(@plataforma)

    get platform_organizations_path
    assert_response :success
    assert_match(/Organização de Teste/, response.body)
    assert_match(/admin-a@exemplo\.com/, response.body)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CANAL)}|MIC ALFA|30000001/, response.body)

    get platform_organization_path(default_organization)
    assert_response :success
    assert_match(/convidado@exemplo\.com/, response.body)
    assert_match(/Convidado por|Teste/, response.body)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CANAL)}|MIC ALFA|30000001/, response.body)
  end

  test "criar organização cria o administrador junto, sem nome e com senha provisória visível" do
    sign_in_as(@plataforma)

    assert_difference [ -> { Organization.count }, -> { User.count } ], 1 do
      post platform_organizations_path, params: { user: { name: "Dona", email_address: "dona@exemplo.com" } }
    end

    dona = User.find_by!(email_address: "dona@exemplo.com")
    assert dona.organization_admin?
    assert_not dona.organization.named?
    assert dona.must_change_password?
    assert_equal 14, dona.provisional_password.length

    follow_redirect!
    assert_match(/#{dona.provisional_password}/, response.body, "a senha fica na tela da organização até a troca")

    criacao = AuditEvent.find_by(action: "organization.created")
    assert_nil criacao.organization, "ação da plataforma não pertence a organização nenhuma"
    assert_equal "dona@exemplo.com", AuditEvent.find_by(action: "organization_admin.created").metadata["alvo"]
  end

  test "adiciona administrador a uma organização que já existe" do
    sign_in_as(@plataforma)

    assert_no_difference -> { Organization.count } do
      post platform_organization_admins_path(default_organization),
        params: { user: { name: "Segundo", email_address: "segundo@exemplo.com" } }
    end

    segundo = User.find_by!(email_address: "segundo@exemplo.com")
    assert segundo.organization_admin?
    assert_equal default_organization, segundo.organization
  end

  test "suporte: reinicia o segundo fator de um administrador e a trilha fica na plataforma" do
    sign_in_as(@plataforma)

    post reset_mfa_platform_user_path(@admin_a)

    assert_redirected_to platform_organization_path(default_organization)
    assert_not @admin_a.reload.mfa_enabled?
    assert_nil AuditEvent.find_by(action: "user.mfa_reset").organization

    post deactivate_platform_user_path(@admin_a)
    assert_not @admin_a.reload.active?
    post reactivate_platform_user_path(@admin_a)
    assert @admin_a.reload.active?
  end

  test "suporte não alcança outra conta da plataforma" do
    outra = platform_admin_user(email: "outra-plataforma@exemplo.com")
    sign_in_as(@plataforma)

    post reset_mfa_platform_user_path(outra)

    assert_response :forbidden
    assert outra.reload.mfa_enabled?
  end

  test "a plataforma não convida colaboradores nem abre a ficha de ninguém" do
    sign_in_as(@plataforma)

    get new_user_path
    assert_response :forbidden
    # 404, não 403: a listagem de usuários da organização não alcança a plataforma.
    get user_path(@admin_a)
    assert_response :not_found
    post users_path, params: { user: { name: "X", email_address: "x@exemplo.com" }, permissions: [], grants: {} }
    assert_response :forbidden
  end

  test "o administrador da organização não abre as telas da plataforma" do
    sign_in_as(@admin_a)

    get platform_organizations_path
    assert_response :forbidden
    post platform_organizations_path, params: { user: { name: "X", email_address: "x@exemplo.com" } }
    assert_response :forbidden
    post reset_mfa_platform_user_path(@convidado)
    assert_response :forbidden
  end
end
