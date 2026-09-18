require "test_helper"

class MetabaseControllerTest < ActionDispatch::IntegrationTest
  test "mostra a conexão somente leitura" do
    get metabase_path

    assert_response :success
    assert_select "h1", text: "Metabase"
    assert_select "td", text: MetabaseRole::NAME
    AuditViews::NAMES.each do |view|
      assert_select "li", text: view
    end
  end

  # O Caddy em outra máquina serve fiserv-metabase.bin para a rede; localhost só vale no host.
  test "link para abrir o Metabase vem de METABASE_URL" do
    original = ENV["METABASE_URL"]
    ENV["METABASE_URL"] = "http://fiserv-metabase.bin"

    get metabase_path

    assert_select "a[href=?]", "http://fiserv-metabase.bin", text: /Abrir Metabase/
    assert_select ".metric-hint", text: /Desligado nesta versão/, count: 0
  ensure
    ENV["METABASE_URL"] = original
  end

  # Sem a variável, o serviço está desligado (é o estado do berry): a tela diz isso em vez de
  # deixar o botão apontar para um endereço que não responde sem explicação.
  test "sem METABASE_URL o link cai em localhost:3001 e a tela avisa que o serviço está desligado" do
    original = ENV.delete("METABASE_URL")

    get metabase_path

    assert_select "a[href=?]", "http://localhost:3001", text: /Abrir Metabase/
    assert_select ".metric-hint", text: /Desligado nesta versão/
  ensure
    ENV["METABASE_URL"] = original if original
  end

  # É o que o docker-compose.berry.yml entrega enquanto o Metabase está fora: a variável existe,
  # vazia. Antes o aviso só saía com ela ausente, e no container ela nunca está ausente.
  test "METABASE_URL vazia conta como desligado" do
    original = ENV["METABASE_URL"]
    ENV["METABASE_URL"] = ""

    get metabase_path

    assert_select "a[href=?]", "http://localhost:3001", text: /Abrir Metabase/
    assert_select ".metric-hint", text: /Desligado nesta versão/
  ensure
    ENV["METABASE_URL"] = original
  end
end

# O layout mostra a idade do último arquivo duas vezes (badge do menu e status do header),
# cada uma chamando ImportBatch.days_since_last_file. O banco só é consultado uma vez porque
# o query cache da requisição absorve a repetição; este teste fixa isso para que ninguém
# "otimize" com um helper memoizado nem quebre a garantia ao mudar a consulta.
class LayoutFileAgeTest < ActionDispatch::IntegrationTest
  include ActiveRecord::Assertions::QueryAssertions

  test "a idade do último arquivo é consultada uma vez por página" do
    assert_queries_match(/MAX\(batch\.created_at\)/, count: 1) { get metabase_path }

    assert_response :success
    assert_select ".nav-badge", text: "Nunca"
    assert_select ".header-status", text: /sem arquivo/
  end
end
