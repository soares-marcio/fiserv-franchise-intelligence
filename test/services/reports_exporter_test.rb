require "test_helper"
require "csv"
require "roo"

class ReportsExporterTest < ActiveSupport::TestCase
  setup do
    @rows = [
      { "sub_channel_name" => "MIC ALFA", "max_known_day" => 10,
        "previous_full_revenue" => "1000.0", "previous_revenue" => "400.0",
        "current_revenue" => "500.0" },
      { "sub_channel_name" => "MIC BETA", "max_known_day" => 10,
        "previous_full_revenue" => "800.0", "previous_revenue" => "200.0",
        "current_revenue" => "100.0" }
    ]
    @totals = { previous_full_revenue: 1800.to_d, previous_revenue: 600.to_d, current_revenue: 600.to_d }
  end

  test "csv traz cabeçalho, uma linha por subcanal e o total" do
    table = CSV.parse(exporter.to_csv, headers: true)

    assert_equal ReportsExporter::HEADERS, table.headers
    assert_equal [ "MIC ALFA", "MIC BETA", "TOTAL" ], table.map { |row| row["Sub-canal"] }
    assert_equal "400.0", table[0]["Mês anterior comparável"]
    assert_equal "1000.0", table[0]["Mês anterior (cheio)"]
  end

  test "a variação usa a base comparável, não o mês cheio" do
    table = CSV.parse(exporter.to_csv, headers: true)

    assert_equal "25.0", table[0]["Variação alinhada %"]
    assert_equal "-50.0", table[1]["Variação alinhada %"]
    assert_equal "0.0", table[2]["Variação alinhada %"]
  end

  test "variação fica vazia quando não há base de comparação" do
    zerado = [ @rows.first.merge("previous_revenue" => "0.0") ]
    table = CSV.parse(
      ReportsExporter.new(zerado, cutoff_day: 10, totals: nil).to_csv, headers: true
    )

    assert_nil table[0]["Variação alinhada %"]
  end

  test "xlsx abre com a nota do corte e as mesmas linhas do csv" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-export.xlsx")
    File.binwrite(path, exporter.to_xlsx)
    sheet = Roo::Excelx.new(path.to_s)

    assert_match(/até o dia 10/, sheet.row(1).first)
    assert_equal ReportsExporter::HEADERS, sheet.row(2)
    assert_equal "MIC ALFA", sheet.row(3).first
    assert_equal "TOTAL", sheet.row(5).first
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  private

  def exporter
    ReportsExporter.new(@rows, cutoff_day: 10, totals: @totals)
  end
end
