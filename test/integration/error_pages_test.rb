require "test_helper"

# Quem usa o portal não sabe o que "404" quer dizer: cada página de erro diz o que aconteceu,
# o que fazer, e só no rodapé o código — explicado, para ser citado a quem dá suporte
# (homologação de 06/10/2026). As estáticas abrem com o app fora do ar e por isso não
# dependem dele, nem para a fonte.
class ErrorPagesTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  STATIC_PAGES = { "400" => "400.html", "404" => "404.html", "406" => "406-unsupported-browser.html",
    "422" => "422.html", "500" => "500.html" }.freeze

  test "cada página estática diz o que aconteceu, o que fazer e explica o código" do
    STATIC_PAGES.each do |code, file|
      html = Nokogiri::HTML(Rails.public_path.join(file).read)

      assert html.at_css("h1")&.text.present?, "#{file} sem título"
      assert html.at_css(".error-next")&.text.present?, "#{file} sem o que fazer"
      assert_match(/Código #{code}.*ajuda/m, html.at_css(".error-code")&.text.to_s, "#{file} sem o código explicado")
      assert_no_match(/\AErro \d/, html.at_css("h1").text, "#{file} abre pelo código")
    end
  end

  test "a fonte das páginas estáticas é servida sem o app compilar nada" do
    assert Rails.public_path.join("fonts/montserrat-latin.woff2").exist?
    assert_match "/fonts/montserrat-latin.woff2", Rails.public_path.join("error.css").read
  end

  test "o 403 segue o mesmo padrão" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: nil))

    get recurring_reports_path

    assert_response :forbidden
    assert_select ".error-next"
    assert_select ".error-code", text: /Código 403.*ajuda/m
  end
end
