require "application_system_test_case"

# O cadastro do segundo fator é o único POST do app que responde com uma tela (os códigos
# de recuperação) em vez de redirecionar — e o Turbo ignora resposta 200 a envio de
# formulário. Na homologação de 28/09/2026 o cadastro gravava e a tela não saía do lugar;
# os testes de integração não pegam porque não executam Turbo. Este pega.
class MfaEnrollmentTest < ApplicationSystemTestCase
  self.skip_default_login = true

  test "concluir o cadastro mostra os códigos de recuperação" do
    newcomer = create_user(email: "novato@exemplo.com", otp_secret: nil, mfa_enabled_at: nil)
    sign_in_through_ui(newcomer)

    assert_text "Segundo fator"
    fill_in "Código gerado pelo aplicativo", with: current_otp(newcomer.reload)
    click_on "Concluir cadastro"

    # O formulário sai sem Turbo e a resposta é a página dos códigos no mesmo endereço: não há
    # troca de URL para esperar, e na CI a recarga passa dos 2 s padrão — o Capybara procurava
    # a página no meio da troca ("Unable to find xpath /html").
    assert_text "Guarde estes códigos", wait: 15
    assert_selector "li.font-mono", count: RecoveryCode::HOW_MANY
    assert newcomer.reload.mfa_enabled?
  end
end
