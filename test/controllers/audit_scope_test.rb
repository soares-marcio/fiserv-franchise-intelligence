require "test_helper"

# A trilha é recortada como tudo o mais: cada organização lê a sua, a plataforma lê só o que
# é de plataforma, e o delegado não lê o login de quem não alcança.
class AuditScopeTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @canal_a = Channel.create!(organization: default_organization, external_id: "9911", name: "MASTER A")
    @canal_a2 = Channel.create!(organization: default_organization, external_id: "9912", name: "MASTER A2")
    @org_b = Organization.create!(name: "Organização B")
    @canal_b = Channel.create!(organization: @org_b, external_id: "9921", name: "MASTER B")

    @admin_a = admin_user(email: "admin-a@exemplo.com")
    @admin_b = create_user(email: "admin-b@exemplo.com", organization: @org_b, organization_admin: true)
    @plataforma = platform_admin_user

    # Um evento de cada natureza: com canal, sem canal (login) e de plataforma.
    Audit.record("batch.uploaded", user: @admin_a, channel: @canal_a, metadata: { arquivo: "a.xlsx" })
    Audit.record("session.start", user: @admin_a)
    Audit.record("batch.uploaded", user: @admin_b, channel: @canal_b, metadata: { arquivo: "b.xlsx" })
    Audit.record("session.start", user: @admin_b)
    Audit.record("organization.created", user: @plataforma, metadata: { alvo: "b" })
  end

  test "cada evento nasce com a organização do ator, e o de plataforma sem nenhuma" do
    assert_equal default_organization, AuditEvent.find_by(user: @admin_a, action: "batch.uploaded").organization
    assert_equal @org_b, AuditEvent.find_by(user: @admin_b, action: "session.start").organization
    assert_nil AuditEvent.find_by(action: "organization.created").organization
  end

  test "o administrador de A lê só a trilha de A" do
    sign_in_as(@admin_a)

    get audit_events_path

    assert_response :success
    assert_match(/a\.xlsx/, response.body)
    assert_no_match(/b\.xlsx|admin-b@exemplo\.com|Criou organização/, response.body)
  end

  test "a plataforma lê só os eventos de plataforma" do
    sign_in_as(@plataforma)

    get audit_events_path

    assert_response :success
    assert_match(/Criou organização/, response.body)
    assert_no_match(/a\.xlsx|b\.xlsx|admin-a@exemplo\.com/, response.body)
  end

  # O vazamento antigo: `.or(channel_id: nil)` mostrava o login de todo usuário do portal a
  # qualquer delegado. Agora só dos usuários que ele alcança.
  test "o delegado não vê o login de quem não alcança, mesmo dentro da organização" do
    delegado = scoped_user(permissions: [ Permission::USERS_INVITE ], channel: @canal_a, email: "delegado@exemplo.com")
    de_outro_master = scoped_user(permissions: [], channel: @canal_a2, email: "longe@exemplo.com")
    Audit.record("session.start", user: de_outro_master)
    do_meu_master = scoped_user(permissions: [], channel: @canal_a, email: "perto@exemplo.com")
    Audit.record("session.start", user: do_meu_master)
    sign_in_as(delegado)

    get audit_events_path

    assert_response :success
    assert_match(/perto@exemplo\.com/, response.body)
    assert_no_match(/longe@exemplo\.com|admin-b@exemplo\.com|Criou organização/, response.body)
    assert_match(/a\.xlsx/, response.body, "evento com canal do Master dele continua visível")
  end
end
