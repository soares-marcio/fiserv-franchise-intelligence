require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "renders the audit page without data" do
    get reports_path
    assert_response :success
    assert_select "h1", text: "Auditoria de faturamento"
    assert_select "th", text: /Mês anterior cheio/
    assert_select "th", text: /Mês anterior comparável/
  end

  test "exports csv" do
    get reports_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Mês anterior (cheio)"
    assert_includes response.body, "Mês anterior comparável"
  end

  test "selects a channel and preserves it in exports" do
    selected = Channel.create!(external_id: "1", canal: "CANAL A")
    Channel.create!(external_id: "2", canal: "CANAL B")

    get reports_path(channel_id: selected.uuid)

    assert_response :success
    assert_select "select[name='channel_id'] option[selected]", text: "CANAL A"
    assert_select "select[name='channel_id'] option", text: "CANAL B"
    assert_select "a[href='#{reports_path(format: :csv, channel_id: selected.uuid)}']", text: "Exportar CSV"
    assert_select "a[href='#{reports_path(format: :xlsx, channel_id: selected.uuid)}']", text: "Exportar XLSX"
  end
end
