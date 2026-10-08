require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  VIEWPORTS = {
    narrow_phone: [ 320, 568 ],
    phone: [ 375, 667 ],
    modern_phone: [ 390, 844 ],
    tablet: [ 768, 1024 ],
    desktop_edge: [ 1024, 768 ],
    desktop: [ 1280, 900 ],
    wide_desktop: [ 1400, 1000 ]
  }.freeze

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
    # Quem já tem o segundo fator cai no desafio; quem ainda não tem vai para o cadastro.
    # exact: o cadastro tem "Código gerado pelo aplicativo", que não é o desafio.
    if has_field?("Código", exact: true, wait: 5)
      fill_in "Código", with: current_otp(user)
      click_on "Verificar"
      # O Turbo envia o formulário em segundo plano: devolver antes de a resposta chegar
      # deixa o teste navegar sem sessão e cair no login. Os 2 s padrão do Capybara não
      # bastam com a máquina carregada: a verificação chegou a passar disso (06/10/2026).
      assert_no_current_path mfa_path, wait: 15
    end
    user
  end

  def with_viewport(name)
    width, height = VIEWPORTS.fetch(name)
    page.driver.browser.manage.window.resize_to(width, height)
    yield width, height
  ensure
    page.driver.browser.manage.window.resize_to(*VIEWPORTS.fetch(:wide_desktop))
  end

  def assert_page_fits_viewport(label: current_path)
    overflow = page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth")
    offenders = if overflow.positive?
      page.evaluate_script(<<~JS)
        [...document.body.querySelectorAll("*")]
          .filter((element) => {
            const bounds = element.getBoundingClientRect()
            return element.offsetParent !== null &&
              (bounds.right > window.innerWidth + 1 || bounds.left < -1)
          })
          .slice(0, 8)
          .map((element) => {
            const bounds = element.getBoundingClientRect()
            return `${element.tagName.toLowerCase()}.${element.className} ` +
              `(left=${Math.round(bounds.left)}, right=${Math.round(bounds.right)}, ` +
              `width=${Math.round(bounds.width)})`
          })
      JS
    end

    assert_operator overflow, :<=, 0,
      "#{label} não pode criar overflow horizontal na página: #{offenders&.join(', ')}"
  end

  def assert_touch_targets(selector, minimum: 44)
    failures = page.evaluate_script(<<~JS, selector, minimum)
      ((selector, minimum) => [...document.querySelectorAll(selector)]
        .filter((element) => element.offsetParent !== null && !element.disabled)
        .map((element) => {
          const bounds = element.getBoundingClientRect()
          return { label: element.getAttribute("aria-label") || element.textContent.trim(),
            width: bounds.width, height: bounds.height }
        })
        .filter((target) => target.width < minimum || target.height < minimum)
      )(arguments[0], arguments[1])
    JS

    assert_empty failures, "alvos menores que #{minimum}px: #{failures.inspect}"
  end
end
