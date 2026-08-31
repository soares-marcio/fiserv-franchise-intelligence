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
end
