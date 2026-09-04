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
  ensure
    ENV["METABASE_URL"] = original
  end

  test "sem METABASE_URL o link cai em localhost:3001" do
    original = ENV.delete("METABASE_URL")

    get metabase_path

    assert_select "a[href=?]", "http://localhost:3001", text: /Abrir Metabase/
  ensure
    ENV["METABASE_URL"] = original if original
  end
end
