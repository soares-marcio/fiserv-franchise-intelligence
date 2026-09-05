require "test_helper"

# A política só vale se o app não depender de nada de fora e de nada inline. Estes testes
# fixam as duas metades: o cabeçalho existe e é fechado, e a página não traz origem externa
# nem script solto que a política bloquearia sem ninguém perceber.
class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  PAGES = %w[/ /establishments /import_batches /metabase].freeze

  test "toda resposta declara a política e ela é fechada na própria origem" do
    PAGES.each do |page|
      get page
      policy = response.headers["Content-Security-Policy"]

      assert_predicate policy.to_s, :present?, "#{page} sem política"
      assert_includes policy, "default-src 'self'", page
      assert_includes policy, "object-src 'none'", page
      assert_includes policy, "base-uri 'self'", page
      assert_includes policy, "frame-ancestors 'none'", page
    end
  end

  test "o importmap recebe o nonce da requisição" do
    get root_path
    nonce = css_select("meta[name='csp-nonce']").first["content"]

    assert_predicate nonce, :present?
    assert_select "script[nonce=?]", nonce
    assert_includes response.headers["Content-Security-Policy"], "'nonce-#{nonce}'"
  end

  # Fonte e ícones vieram para dentro do repositório; um recurso externo aqui voltaria a
  # vazar o acesso da rede interna para fora e seria bloqueado em silêncio. Link de navegação
  # não conta: o do Metabase aponta para outro host por definição, e a política não o alcança.
  test "nenhuma página carrega recurso de origem externa" do
    PAGES.each do |page|
      get page

      externos = css_select("script[src^='http'], link[rel='stylesheet'][href^='http'], " \
        "img[src^='http'], link[rel='preconnect'], link[rel='modulepreload'][href^='http']")

      assert_empty externos.map { |tag| tag["src"] || tag["href"] }, "#{page} carrega recurso externo"
    end
  end
end
