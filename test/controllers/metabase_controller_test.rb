require "test_helper"

# A tela do Metabase mostra a conexão de um papel que lê as views de todas as organizações.
# Até haver recorte por organização no Metabase, ela está fechada para todos — inclusive
# para o administrador da organização e para quem já tinha a chave antiga.
class MetabaseControllerTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  test "fechada para todos até haver recorte por organização" do
    sign_in_as(admin_user)
    get metabase_path
    assert_response :forbidden
    sign_out

    travel 31.seconds
    sign_in_as(scoped_user(permissions: [ Permission::METABASE_READ ], email: "antigo@exemplo.com"))
    get metabase_path
    assert_response :forbidden
  end

  test "a chave não é oferecida no convite" do
    sign_in_as(admin_user)

    get new_user_path

    assert_select "input[name='permissions[]'][value=?]", Permission::METABASE_READ, count: 0
  end
end

# O staging roda a mesma imagem que a produção, com uma cópia dos dados reais: a faixa é o
# único sinal na tela de que aquele não é o ambiente verdadeiro.
class StagingBannerTest < ActionDispatch::IntegrationTest
  test "a faixa de homologação aparece quando APP_ENVIRONMENT=staging" do
    original = ENV["APP_ENVIRONMENT"]
    ENV["APP_ENVIRONMENT"] = "staging"

    get reports_path

    assert_select ".env-banner", text: /Homologação/
  ensure
    ENV["APP_ENVIRONMENT"] = original
  end

  test "sem a variável a faixa não existe" do
    original = ENV.delete("APP_ENVIRONMENT")

    get reports_path

    assert_select ".env-banner", count: 0
  ensure
    ENV["APP_ENVIRONMENT"] = original if original
  end
end

# O layout mostra a idade do último arquivo duas vezes (badge do menu e status do header),
# cada uma chamando ImportBatch.days_since_last_file. O banco só é consultado uma vez porque
# o query cache da requisição absorve a repetição; este teste fixa isso para que ninguém
# "otimize" com um helper memoizado nem quebre a garantia ao mudar a consulta.
class LayoutFileAgeTest < ActionDispatch::IntegrationTest
  include ActiveRecord::Assertions::QueryAssertions

  test "a idade do último arquivo é consultada uma vez por página" do
    assert_queries_match(/MAX\(batch\.created_at\)/, count: 1) { get reports_path }

    assert_response :success
    assert_select ".nav-badge", text: "Nunca"
    assert_select ".header-status", text: /sem arquivo/
  end
end
