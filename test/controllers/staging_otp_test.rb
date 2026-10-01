require "test_helper"

# A homologação mostra o código do autenticador na tela para testar sem celular. O teste
# que importa é o negativo: sem APP_ENVIRONMENT=staging o código não pode aparecer nunca —
# a imagem é a mesma da produção.
class StagingOtpTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @original = ENV["APP_ENVIRONMENT"]
    @user = admin_user
  end

  teardown do
    @original ? ENV["APP_ENVIRONMENT"] = @original : ENV.delete("APP_ENVIRONMENT")
  end

  test "em homologação, o desafio mostra o código válido do usuário" do
    ENV["APP_ENVIRONMENT"] = "staging"
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }

    get mfa_path

    assert_select "[data-testid=staging-otp]", text: current_otp(@user)
  end

  test "em homologação, o cadastro do segundo fator mostra o código do segredo recém-gerado" do
    ENV["APP_ENVIRONMENT"] = "staging"
    newcomer = create_user(email: "novato@exemplo.com", otp_secret: nil, mfa_enabled_at: nil)
    post session_path, params: { email_address: newcomer.email_address, password: Accounts::PASSWORD }

    get mfa_enrollment_path

    assert_select "[data-testid=staging-otp]", text: current_otp(newcomer.reload)
  end

  test "fora da homologação, nenhuma das duas telas mostra código" do
    ENV.delete("APP_ENVIRONMENT")
    post session_path, params: { email_address: @user.email_address, password: Accounts::PASSWORD }

    get mfa_path
    assert_select "[data-testid=staging-otp]", count: 0
    assert_no_match current_otp(@user), response.body

    newcomer = create_user(email: "novato@exemplo.com", otp_secret: nil, mfa_enabled_at: nil)
    post session_path, params: { email_address: newcomer.email_address, password: Accounts::PASSWORD }
    get mfa_enrollment_path
    assert_select "[data-testid=staging-otp]", count: 0
  end
end
