require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Vários controles da interface só têm rótulo acessível (aria-label): o botão de mês do
  # calendário, o "×" do chip. Procurar por esse rótulo nos testes é procurar pelo mesmo
  # texto que o leitor de tela anuncia.
  Capybara.enable_aria_label = true

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
  end

  class_attribute :skip_default_login, default: false

  setup { sign_in_through_ui(admin_user) unless self.class.skip_default_login }

  # Pela interface, preenchendo os mesmos campos que a pessoa preenche: é o que garante que
  # a tela de entrada continua utilizável, e não só que a sessão pode ser forjada.
  def sign_in_through_ui(user, password: Accounts::PASSWORD)
    visit new_session_path
    fill_in "E-mail", with: user.email_address
    fill_in "Senha", with: password
    click_on "Entrar"
    user
  end
end
