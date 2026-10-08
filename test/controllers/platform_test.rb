require "test_helper"

# A conta da plataforma: cria organizações e o administrador de cada uma, vê quem existe,
# presta suporte — e não lê dado de organização nenhuma.
class PlatformTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    import_synthetic_workbook
    @platform = platform_admin_user
    @admin_a = admin_user(email: "admin-a@exemplo.com")
    @guest = scoped_user(permissions: [ *Permission::REPORT_KEYS ], channel: Channel.first,
      email: "convidado@exemplo.com", created_by: @admin_a)
  end

  test "ao entrar, a plataforma cai na tela de organizações, não em relatório" do
    sign_in_as(@platform)

    get root_path

    assert_redirected_to platform_organizations_path
  end

  test "a tela macro lista organizações, administradores e convidados sem nome de Master" do
    Audit.record("session.start", user: @guest)
    sign_in_as(@platform)

    get platform_organizations_path
    assert_response :success
    assert_match(/Organização de Teste/, response.body)
    assert_match(/admin-a@exemplo\.com/, response.body)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}|MIC ALFA|30000001/, response.body)

    get platform_organization_path(default_organization)
    assert_response :success
    assert_match(/convidado@exemplo\.com/, response.body)
    assert_match(/Convidado por|Teste/, response.body)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}|MIC ALFA|30000001/, response.body)
  end

  test "criar organização cria o administrador junto, sem nome e com senha provisória visível" do
    sign_in_as(@platform)

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

    creation = AuditEvent.find_by(action: "organization.created")
    assert_nil creation.organization, "ação da plataforma não pertence a organização nenhuma"
    assert_equal "dona@exemplo.com", AuditEvent.find_by(action: "organization_admin.created").metadata["alvo"]
  end

  test "adiciona administrador a uma organização que já existe" do
    sign_in_as(@platform)

    assert_no_difference -> { Organization.count } do
      post platform_organization_admins_path(default_organization),
        params: { user: { name: "Segundo", email_address: "segundo@exemplo.com" } }
    end

    second = User.find_by!(email_address: "segundo@exemplo.com")
    assert second.organization_admin?
    assert_equal default_organization, second.organization
  end

  test "suporte: reinicia o segundo fator de um administrador e a trilha fica na plataforma" do
    sign_in_as(@platform)

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
    other = platform_admin_user(email: "outra-plataforma@exemplo.com")
    sign_in_as(@platform)

    post reset_mfa_platform_user_path(other)

    assert_response :forbidden
    assert other.reload.mfa_enabled?
  end

  test "a plataforma não convida colaboradores nem abre a ficha de ninguém" do
    sign_in_as(@platform)

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
    post reset_mfa_platform_user_path(@guest)
    assert_response :forbidden
  end

  test "a ficha da organização traz contagens e datas, sem nome de Master" do
    sign_in_as(@platform)

    get platform_organization_path(default_organization)

    assert_response :success
    assert_match(/Masters<\/dt><dd class="font-semibold tabular-nums">1</, response.body)
    assert_match(/Arquivos importados<\/dt><dd class="font-semibold tabular-nums">1</, response.body)
    assert_match(/Administradores<\/dt><dd class="font-semibold tabular-nums">1</, response.body)
    assert_match(/Colaboradores<\/dt><dd class="font-semibold tabular-nums">1</, response.body)
    assert_match(/Anexos<\/dt><dd class="font-semibold tabular-nums">0 · 0 Bytes/, response.body)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}|MIC ALFA|30000001/, response.body)
  end

  # A plataforma acompanha por quanto tempo cada convidado vai usar o portal — base para
  # cobrança por usuário e para saber quem sai em breve (pedido de 07/10/2026).
  test "a ficha mostra a validade de cada convidado e a contagem dos prazos" do
    other = scoped_user(permissions: [ *Permission::REPORT_KEYS ], channel: Channel.first,
      email: "temporario@exemplo.com", created_by: @admin_a)
    other.update_column(:access_expires_on, 3.days.from_now.to_date)
    gone = scoped_user(permissions: [ *Permission::REPORT_KEYS ], channel: Channel.first,
      email: "vencido@exemplo.com", created_by: @admin_a)
    gone.update_column(:access_expires_on, 2.days.ago.to_date)
    sign_in_as(@platform)

    get platform_organization_path(default_organization)

    assert_select "th", text: "Validade"
    assert_match "Indeterminada", response.body
    assert_match "vence em 3 dias", response.body
    assert_match "venceu em", response.body
    assert_match(/Com prazo<\/dt><dd class="font-semibold tabular-nums">2</, response.body)
    assert_match(/Vencem em 7 dias<\/dt><dd class="font-semibold tabular-nums">1</, response.body)
    assert_match(/Vencidos<\/dt><dd class="font-semibold tabular-nums">1</, response.body)
  end

  test "renomeia a organização a pedido, com o nome anterior e o novo na trilha" do
    sign_in_as(@platform)

    patch rename_platform_organization_path(default_organization), params: { name: "Nome Novo" }

    assert_redirected_to platform_organization_path(default_organization)
    assert_equal "Nome Novo", default_organization.reload.name
    event = AuditEvent.find_by!(action: "organization.renamed")
    assert_nil event.organization
    assert_equal({ "de" => "Organização de Teste", "para" => "Nome Novo" }, event.metadata)
  end

  test "renomear recusa nome em branco e nome já usado" do
    Organization.create!(name: "Ocupado")
    sign_in_as(@platform)

    patch rename_platform_organization_path(default_organization), params: { name: "   " }
    assert_equal "Organização de Teste", default_organization.reload.name
    assert_match(/em branco/, flash[:alert])

    patch rename_platform_organization_path(default_organization), params: { name: "Ocupado" }
    assert_equal "Organização de Teste", default_organization.reload.name
    assert_nil AuditEvent.find_by(action: "organization.renamed")
  end

  test "suspender derruba as sessões, fecha a entrada com a mensagem neutra e reativar reabre" do
    sign_in_as(@admin_a)
    assert_equal 1, @admin_a.sessions.count

    sign_in_as(@platform)
    post suspend_platform_organization_path(default_organization)

    assert_redirected_to platform_organization_path(default_organization)
    assert default_organization.reload.suspended?
    assert_equal 0, @admin_a.sessions.count
    assert_nil AuditEvent.find_by!(action: "organization.suspended").organization

    follow_redirect!
    assert_match(/Suspensa/, response.body)
    get platform_organizations_path
    assert_match(/Suspensa/, response.body)

    sign_out
    travel 31.seconds
    post session_path, params: { email_address: @admin_a.email_address, password: PASSWORD }
    assert_redirected_to new_session_path(email_address: @admin_a.email_address)
    assert_equal "E-mail ou senha inválidos.", flash[:alert]
    assert_equal 0, @admin_a.sessions.count

    sign_in_as(@platform)
    post reactivate_platform_organization_path(default_organization)
    assert_not default_organization.reload.suspended?
    sign_out

    travel 31.seconds
    sign_in_as(@admin_a)
    get reports_path
    assert_response :success
  end

  test "suspensa no meio do segundo fator, a pessoa não entra" do
    post session_path, params: { email_address: @admin_a.email_address, password: PASSWORD }
    assert_redirected_to mfa_path

    default_organization.suspend!
    post mfa_path, params: { code: current_otp(@admin_a) }

    assert_redirected_to new_session_path
    assert_equal 0, @admin_a.sessions.count
  end

  test "a ficha mostra o que a plataforma fez nesta organização, e não em outra" do
    other = Operations::CreateOrganizationAdmin.call(name: "Fulana", email_address: "fulana@exemplo.com", actor: @platform)
    sign_in_as(@platform)
    post reset_mfa_platform_user_path(@admin_a)
    post reset_mfa_platform_user_path(other)

    get platform_organization_path(default_organization)

    assert_match(/Reiniciou o segundo fator de alguém/, response.body)
    assert_match(/alvo: admin-a@exemplo\.com/, response.body)
    assert_no_match(/fulana@exemplo\.com/, response.body)
  end

  test "o administrador da organização não renomeia nem suspende pela plataforma" do
    sign_in_as(@admin_a)

    patch rename_platform_organization_path(default_organization), params: { name: "X" }
    assert_response :forbidden
    post suspend_platform_organization_path(default_organization)
    assert_response :forbidden
    assert_not default_organization.reload.suspended?
  end

  test "a ficha e as telas internas têm Voltar apontando para a tela anterior; a lista não" do
    sign_in_as(@platform)

    get platform_organizations_path
    assert_select "a.breadcrumb-back", count: 0

    get platform_organization_path(default_organization)
    assert_select "a.breadcrumb-back[href=?]", platform_organizations_path, text: /Voltar/

    get new_platform_organization_admin_path(default_organization)
    assert_select "a.breadcrumb-back[href=?]", platform_organization_path(default_organization)
  end

  test "desativar o último administrador ativo suspende a organização; reativá-lo reabre" do
    sign_in_as(@platform)

    post deactivate_platform_user_path(@admin_a)

    assert default_organization.reload.suspended?
    assert_equal "último administrador desativado", AuditEvent.find_by!(action: "organization.suspended").metadata["motivo"]
    assert_match(/suspensa junto/, flash[:notice])

    post reactivate_platform_user_path(@admin_a)

    assert_not default_organization.reload.suspended?
    assert_match(/reaberta junto/, flash[:notice])
  end

  test "com outro administrador ativo, desativar um deles não suspende a organização" do
    admin_user(email: "admin-b@exemplo.com")
    sign_in_as(@platform)

    post deactivate_platform_user_path(@admin_a)

    assert_not default_organization.reload.suspended?
    assert_nil AuditEvent.find_by(action: "organization.suspended")
  end

  test "o histórico da organização mostra a atividade dela sem o nome do Master" do
    Audit.record("batch.uploaded", user: @admin_a, channel: Channel.first, metadata: { arquivo: "x.xlsx" })
    Audit.record("session.start", user: @guest)
    sign_in_as(@platform)

    get history_platform_organization_path(default_organization)

    assert_response :success
    assert_match(/Enviou planilha/, response.body)
    assert_match(/convidado@exemplo\.com/, response.body)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}|MIC ALFA|30000001/, response.body)
    assert_select "a.breadcrumb-back[href=?]", platform_organization_path(default_organization)

    sign_out
    travel 31.seconds
    sign_in_as(@admin_a)
    get history_platform_organization_path(default_organization)
    assert_response :forbidden
  end
end
