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
end
