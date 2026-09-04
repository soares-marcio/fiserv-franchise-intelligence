require "test_helper"

# Toda tabela do portal é larga e rola na horizontal. Sem scope, o leitor de tela não sabe
# a que coluna cada célula pertence; sem região focável, quem navega por teclado não
# consegue rolar a tabela. Este teste vale para as telas todas de uma vez: tabela nova sem
# esses atributos nasce reprovada.
class TableAccessibilityTest < ActionDispatch::IntegrationTest
  setup do
    import_synthetic_workbook
    refresh_audit_views
    @sub_channel = SubChannel.find_by!(name: "MIC ALFA")
  end

  # A tabela de dados de conexão do Metabase fica de fora: ela rotula linhas, não colunas,
  # e tem teste próprio abaixo.
  def paths
    [
      reports_path, stalled_reports_path, weekly_reports_path, recurring_reports_path,
      three_months_reports_path, establishments_path, import_batches_path,
      sub_channel_report_path(@sub_channel)
    ]
  end

  test "todo cabeçalho de coluna declara o próprio escopo" do
    paths.each do |path|
      get path

      assert_response :success, path
      headers = css_select("thead th")
      assert_predicate headers, :any?, "#{path} sem cabeçalho de tabela"
      headers.each do |header|
        assert_equal "col", header["scope"], "#{path}: #{header.text.strip.truncate(30)}"
      end
    end
  end

  test "cabeçalho sem texto tem rótulo para quem não enxerga a coluna" do
    get import_batches_path

    assert_select "thead th[scope='col'] span.sr-only", text: "Ações"
  end

  test "a tabela de dados de conexão do Metabase rotula as linhas" do
    get metabase_path

    assert_select "tbody th[scope='row']", text: "Porta"
    assert_select "tbody th[scope='row']", text: "Database"
  end

  test "a área rolável da tabela é alcançável pelo teclado e se anuncia" do
    paths.each do |path|
      get path

      css_select("div.table-scroll").each do |region|
        assert_equal "region", region["role"], path
        assert_equal "0", region["tabindex"], path
        assert_predicate region["aria-label"].to_s, :present?, "#{path} sem aria-label na área rolável"
      end
    end
  end
end
