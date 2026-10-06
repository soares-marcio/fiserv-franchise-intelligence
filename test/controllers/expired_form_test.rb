require "test_helper"

# Formulário que ficou aberto até o token de segurança vencer (a tela de login esquecida no
# almoço, o convite pela metade) caía na página solta do 422 e perdia o contexto. Volta para
# a tela de onde veio, com o aviso — e só para tela deste portal (homologação de 06/10/2026).
class ExpiredFormTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @forgery_protection }

  test "o login com o formulário vencido volta ao login com o aviso" do
    post session_path, params: { email_address: "x@exemplo.com", password: "x", authenticity_token: "vencido" },
      headers: { "Referer" => "http://www.example.com#{new_session_path}" }

    assert_redirected_to new_session_path
    assert_match "ficou aberta por muito tempo", flash[:alert]
  end

  test "um formulário do portal vencido volta à mesma tela" do
    ActionController::Base.allow_forgery_protection = false
    sign_in_as(admin_user)
    ActionController::Base.allow_forgery_protection = true

    post users_path, params: { user: { name: "X", email_address: "x@exemplo.com" }, authenticity_token: "vencido" },
      headers: { "Referer" => "http://www.example.com#{new_user_path}" }

    assert_redirected_to new_user_path
    assert_equal 0, User.where(email_address: "x@exemplo.com").count, "nada é gravado com o token vencido"
  end

  test "origem de outro endereço não é seguida: volta ao início" do
    post session_path, params: { authenticity_token: "vencido" },
      headers: { "Referer" => "https://outro-site.example/phishing" }

    assert_redirected_to root_path
  end
end
