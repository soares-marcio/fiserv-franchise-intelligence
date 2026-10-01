require "test_helper"

# O portão em si. Estes testes conduzem a entrada por conta própria — por isso desligam o
# login automático que os demais usam.
class AuthenticationTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @user = admin_user
  end

  test "sem sessão, qualquer tela leva ao login" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "a tela de entrada identifica o ambiente de homologação" do
    original = ENV["APP_ENVIRONMENT"]
    ENV["APP_ENVIRONMENT"] = "staging"

    get new_session_path

    assert_response :success
    assert_select ".env-banner", text: /Homologação/
  ensure
    original ? ENV["APP_ENVIRONMENT"] = original : ENV.delete("APP_ENVIRONMENT")
  end

  test "a tela pedida é retomada depois de entrar" do
    get metabase_path
    sign_in_as(@user)

    assert_redirected_to metabase_path
  end

  # Caminho vindo de fora não pode virar redirecionamento para outro site depois do login.
  test "destino forjado para outro host é ignorado" do
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }
    session[:return_to_after_authenticating] = "//exemplo.invalido/roubo"
    post mfa_path, params: { code: current_otp(@user) }

    assert_redirected_to root_url
  end

  test "a senha certa ainda não é uma sessão: o segundo fator vem antes" do
    assert_no_difference -> { Session.count } do
      post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }
    end

    assert_redirected_to mfa_path

    get root_path

    assert_redirected_to new_session_path, "sem o código, o portal continua fechado"
  end

  test "e-mail inexistente e senha errada dão a mesma resposta" do
    post session_path, params: { email_address: "ninguem@exemplo.com", password: "qualquer-coisa-12" }
    nonexistent = flash[:alert]

    post session_path, params: { email_address: @user.email_address, password: "senha-errada-123" }

    assert_equal nonexistent, flash[:alert], "a diferença contaria quem existe no portal"
  end

  # Uma conta comum: o último administrador da plataforma ativo não se desativa (User#keep_one_active_platform_admin).
  test "conta desativada não entra, e sem dizer por quê" do
    shared = scoped_user(permissions: [], email: "comum@exemplo.com")
    shared.update!(deactivated_at: Time.current)

    post session_path, params: { email_address: shared.email_address, password: Accounts::PASSWORD }

    assert_redirected_to new_session_path(email_address: shared.email_address)
    assert_equal 0, Session.count
  end

  test "dez senhas erradas bloqueiam a conta, e a senha certa não entra enquanto durar" do
    User::MAX_FAILED_ATTEMPTS.times do
      post session_path, params: { email_address: @user.email_address, password: "errada-mesmo-123" }
    end

    assert @user.reload.locked?

    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }

    assert_match(/bloqueada/i, flash[:alert])
    assert_equal 0, Session.count
  end

  test "o código do autenticador não vale duas vezes" do
    code = current_otp(@user)
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }
    post mfa_path, params: { code: code }

    assert_equal 1, Session.count

    delete session_path
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }
    post mfa_path, params: { code: code }

    assert_equal 0, Session.count, "o mesmo código não pode abrir uma segunda sessão"
  end

  test "código de recuperação entra uma vez só" do
    codes = RecoveryCode.generate_for(@user)
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }
    post mfa_path, params: { code: codes.first }

    assert_equal 1, Session.count
    assert_equal 1, @user.recovery_codes.where.not(used_at: nil).count

    delete session_path
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }
    post mfa_path, params: { code: codes.first }

    assert_equal 0, Session.count, "código gasto não abre sessão de novo"
  end

  test "a verificação expira e manda entrar de novo" do
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }

    travel PendingAuthentication::PENDING_LIMIT + 1.minute do
      post mfa_path, params: { code: current_otp(@user) }

      assert_redirected_to new_session_path
      assert_equal 0, Session.count
    end
  end

  test "sessão parada expira e some do banco" do
    sign_in_as(@user)
    Session.last.update_column(:last_active_at, 3.hours.ago)

    get root_path

    assert_redirected_to new_session_path
    assert_equal 0, Session.count, "sessão expirada não fica viva no banco"
  end

  test "desativar o usuário derruba quem já estava dentro" do
    shared = scoped_user(permissions: [], email: "comum@exemplo.com")
    sign_in_as(shared)
    shared.update!(deactivated_at: Time.current)

    get root_path

    assert_redirected_to new_session_path
    assert_equal 0, Session.count
  end

  test "sair encerra a sessão" do
    sign_in_as(@user)

    assert_difference -> { Session.count }, -1 do
      delete session_path
    end
  end
end

# Pendências que valem mais que qualquer tela: enquanto existirem, o portal não abre.
class AuthenticationPendingStateTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  test "senha provisória leva à troca antes de qualquer tela" do
    user = admin_user(must_change_password: true)
    sign_in_as(user)

    get root_path

    assert_redirected_to edit_password_path
  end

  test "sem segundo fator cadastrado, a inscrição vem antes" do
    user = create_user(email: "novo@exemplo.com", otp_secret: nil, mfa_enabled_at: nil, platform_admin: true)
    post session_path, params: { email_address: user.email_address, password: Accounts::PASSWORD }
    # Sem MFA inscrito não há código a pedir: a sessão nasce e a inscrição é a primeira tela.
    post mfa_path, params: { code: "000000" }
    get root_path

    assert_redirected_to mfa_enrollment_path
  end
end
