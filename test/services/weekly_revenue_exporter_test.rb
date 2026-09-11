require "test_helper"
require "csv"
require "roo"

class WeeklyRevenueExporterTest < ActiveSupport::TestCase
  # Agosto de 2026 coberto só até o dia 3: os outros 28 dias não são zero, são desconhecidos.
  setup do
    @period = Date.new(2026, 8, 1)
    dias = [
      { "day" => 1, "revenue" => "100.0", "establishments" => 2 },
      { "day" => 2, "revenue" => "0.0", "establishments" => 0 },
      { "day" => 3, "revenue" => "250.0", "establishments" => 3 }
    ]
    semanas = [ { "week_start" => "2026-07-26", "revenue" => "100.0", "establishments" => 2 } ]
    @calendar = RevenueCalendar.new(period: @period, covered_days: 3, days: dias, weeks: semanas)
  end

  test "um dia por linha, só os dias que o arquivo cobre" do
    tabela = CSV.parse(exporter.to_csv, headers: true)

    assert_equal WeeklyRevenueExporter::HEADERS, tabela.headers
    dias = tabela.reject { |linha| linha["Semana"] == "TOTAL" }
    assert_equal %w[1 2 3], dias.map { |linha| linha["Dia"] },
      "dia além da cobertura não vira linha zerada: seria afirmar que a carteira não vendeu"
    assert_equal "100.0", dias.first["Faturamento"]
    assert_equal "2", dias.first["ECs com movimento"]
  end

  # Dia coberto sem venda é zero de verdade — é o buraco que se abre a tela para ver.
  test "dia coberto sem venda sai zerado, e não vazio" do
    linha = CSV.parse(exporter.to_csv, headers: true).find { |l| l["Dia"] == "2" }

    assert_equal "0.0", linha["Faturamento"]
    assert_equal "0", linha["ECs com movimento"]
  end

  # Somar ECs por dia contaria o mesmo EC uma vez por dia. A tela fala em "ECs distintos" e
  # apura isso à parte; o arquivo prefere a célula vazia a um número que ninguém apurou.
  test "o total soma o dinheiro e deixa a contagem de ECs em branco" do
    total = CSV.parse(exporter.to_csv, headers: true).find { |l| l["Semana"] == "TOTAL" }

    assert_equal "350.0", total["Faturamento"]
    assert_nil total["ECs com movimento"]
  end

  test "xlsx traz a competência e o recorte na nota do cabeçalho" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-ritmo.xlsx")
    File.binwrite(path, WeeklyRevenueExporter.new(@calendar, period: @period,
      channel_name: "MASTER A").to_xlsx)

    nota = Roo::Excelx.new(path.to_s).row(1).first
    assert_match(/08\/2026/, nota)
    assert_match(/MASTER A/, nota)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  private

  def exporter
    WeeklyRevenueExporter.new(@calendar, period: @period)
  end
end
