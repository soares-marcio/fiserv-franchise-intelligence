require "application_system_test_case"

# Mudar a permissão de alguém derruba as sessões dele. A pessoa é mandada ao login na tela
# seguinte e tem de conseguir entrar de novo de primeira (homologação de 06/10/2026: a
# reentrada caía em "a página ficou aberta por muito tempo").
class ReloginAfterRevocationTest < ApplicationSystemTestCase
  self.skip_default_login = true

  setup do
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    import_synthetic_workbook
    @user = scoped_user(permissions: [ Permission::REPORTS_REVENUE, Permission::REPORTS_CLOVER ],
      channel: Channel.find_by!(name: BinWorkbook::CHANNEL))
  end

  teardown { ActionController::Base.allow_forgery_protection = @forgery_protection }

  test "numa aba: derrubado ao navegar, entra de novo de primeira" do
    sign_in_through_ui(@user)
    assert_link "Clover Capital"

    @user.revoke_sessions!
    click_link "Clover Capital"

    assert_field "E-mail"
    sign_in_again
  end

  # As abas dividem o cookie: a senha aceita numa troca a sessão do navegador e, com ela, a
  # chave dos formulários; o login aberto na outra fica com a chave velha. A recusa é certa,
  # mas a mensagem precisa dizer o que houve, e o segundo envio tem de passar.
  test "em duas abas: a outra aba explica o que houve e entra no segundo envio" do
    sign_in_through_ui(@user)
    second = open_new_window
    within_window(second) { visit reports_path }

    @user.revoke_sessions!
    click_link "Clover Capital"
    assert_field "E-mail"
    within_window(second) do
      click_link "Clover Capital"
      assert_field "E-mail"
    end

    sign_in_again
    within_window(second) do
      submit_credentials
      assert_text "outra aba"
      sign_in_again
    end
  end

  test "em duas abas: se a outra aba já entrou, esta entra direto" do
    sign_in_through_ui(@user)
    second = open_new_window
    within_window(second) { visit reports_path }

    @user.revoke_sessions!
    click_link "Clover Capital"
    within_window(second) do
      click_link "Clover Capital"
      assert_field "E-mail"
    end

    travel 31.seconds # o código do autenticador não vale duas vezes na mesma janela
    sign_in_through_ui(@user)
    within_window(second) do
      submit_credentials
      assert_no_field "E-mail"
      assert_link "Clover Capital"
    end
  end

  # A permissão da tela aberta é tirada: a pessoa é deslogada, e a entrada a levava de volta a
  # essa tela — agora um 403 — e o Turbo, ao recarregar, mostrava "a verificação expirou"
  # com a pessoa já dentro (homologação de 06/10/2026). Entra e cai na primeira tela que tem.
  test "a tela que perdeu a permissão não vira 403 logo depois de entrar" do
    sign_in_through_ui(@user)
    click_link "Clover Capital"
    assert_current_path stalled_reports_path

    @user.update!(permissions: [ Permission::REPORTS_REVENUE ])
    @user.revoke_sessions!
    visit stalled_reports_path
    assert_field "E-mail"

    travel 31.seconds # o código do autenticador não vale duas vezes na mesma janela
    sign_in_through_ui(@user)

    assert_no_text "expirou"
    assert_no_text "não tem permissão"
    assert_current_path reports_path
  end

  private

  def submit_credentials
    fill_in "E-mail", with: @user.email_address
    fill_in "Senha", with: Accounts::PASSWORD
    click_on "Entrar"
  end

  def sign_in_again
    submit_credentials
    assert_no_text "desatualizada"
    assert_field "Código", exact: true, wait: 10
  end
end
