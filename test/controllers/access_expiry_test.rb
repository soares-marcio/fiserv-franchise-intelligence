require "test_helper"

# Validade do acesso: quem administra escolhe até quando a pessoa entra, ou deixa por tempo
# indeterminado (pedido da administradora da organização, 06/10/2026). Vale até o fim do dia
# escolhido, no horário de Brasília; vencido, nada é apagado — renovar devolve o acesso.
class AccessExpiryTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @channel = Channel.create!(organization: default_organization, external_id: "8001", name: "MASTER A")
  end

  test "vale até o fim do dia escolhido e vence no dia seguinte" do
    user = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel)
    user.update_column(:access_expires_on, Date.current)

    assert user.sign_in_allowed?, "o último dia ainda vale"
    travel_to Date.current.tomorrow.beginning_of_day do
      assert user.reload.access_expired?
      assert_not user.sign_in_allowed?
    end
  end

  test "a data precisa ser futura, e administrador não tem prazo" do
    user = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel)

    user.access_expires_on = Date.current
    assert_not user.valid?
    assert_match(/depois de hoje/, user.errors[:access_expires_on].join)

    boss = admin_user(email: "outro-chefe@exemplo.com")
    boss.access_expires_on = 1.month.from_now.to_date
    assert_not boss.valid?
  end

  # Com a senha certa, a pessoa precisa saber o que fazer: "e-mail ou senha inválidos" a
  # faria tentar de novo até o bloqueio. Quem não tem a senha não descobre nada.
  test "acesso vencido, senha certa: avisa antes do segundo fator, sem pedir o código" do
    user = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel)
    user.update_column(:access_expires_on, 2.days.ago.to_date)

    post session_path, params: { email_address: user.email_address, password: Accounts::PASSWORD }

    assert_redirected_to new_session_path(email_address: user.email_address)
    assert_match "Seu acesso venceu em #{I18n.l(2.days.ago.to_date, format: '%d/%m/%Y')}", flash[:alert]
    assert_nil cookies[:pending_mfa], "não chega à tela do código"
  end

  test "acesso vencido, senha errada: a mesma resposta neutra de sempre" do
    user = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel)
    user.update_column(:access_expires_on, 2.days.ago.to_date)

    post session_path, params: { email_address: user.email_address, password: "errada-123" }

    assert_equal "E-mail ou senha inválidos.", flash[:alert]
  end

  test "quem está dentro sai na próxima tela depois que o acesso vence" do
    user = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel)
    user.update_column(:access_expires_on, 1.day.from_now.to_date)
    sign_in_as(user)

    travel 3.days do
      get reports_path
      assert_redirected_to new_session_path
    end
  end

  test "quem administra define a data, e indeterminado apaga o prazo" do
    target = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel, email: "alvo@exemplo.com")
    sign_in_as(admin_user)
    until_date = 1.month.from_now.to_date

    patch user_path(target), params: access_params(target, validity: "until", date: until_date)
    assert_equal until_date, target.reload.access_expires_on
    assert AuditEvent.where(action: "user.access_validity_changed").exists?

    patch user_path(target), params: access_params(target, validity: "indefinite", date: until_date)
    assert_nil target.reload.access_expires_on
  end

  test "o delegado com prazo não dá prazo maior que o dele, nem indeterminado" do
    delegate = scoped_user(permissions: [ Permission::USERS_INVITE, Permission::REPORTS_REVENUE ],
      channel: @channel, email: "delegado@exemplo.com")
    delegate.update_column(:access_expires_on, 10.days.from_now.to_date)
    sign_in_as(delegate)

    post users_path, params: { user: { name: "Nova", email_address: "nova@exemplo.com" },
      access_validity: "indefinite", permissions: [ Permission::REPORTS_REVENUE ],
      grants: { "0" => { channel_id: @channel.id } } }
    assert_response :unprocessable_entity
    assert_match "não pode passar de", response.body

    post users_path, params: { user: { name: "Nova", email_address: "nova@exemplo.com",
      access_expires_on: 5.days.from_now.to_date }, access_validity: "until",
      permissions: [ Permission::REPORTS_REVENUE ], grants: { "0" => { channel_id: @channel.id } } }
    assert_equal 5.days.from_now.to_date, User.find_by!(email_address: "nova@exemplo.com").access_expires_on
  end

  test "a listagem mostra a validade e a própria pessoa é avisada perto do fim" do
    target = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel, email: "alvo@exemplo.com")
    target.update_column(:access_expires_on, 3.days.from_now.to_date)
    sign_in_as(admin_user)

    get users_path
    assert_match "vence em 3 dias", response.body
    sign_out

    travel 31.seconds
    sign_in_as(target)
    get reports_path
    assert_select ".access-expiry-banner", text: /Seu acesso vence em 3 dias/
  end

  private

  def access_params(target, validity:, date:)
    { user: { name: target.name, email_address: target.email_address, access_expires_on: date },
      access_validity: validity, permissions: target.permissions,
      grants: { "0" => { channel_id: @channel.id } } }
  end
end
