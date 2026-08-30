require "test_helper"
require "caxlsx"

class BinImport::ImporterTest < ActiveSupport::TestCase
  SOURCE_FILE = Rails.root.join("1478_MASTER_FRANQUEADO_RAMOS_E_SILVA_20260825.xlsx")

  test "imports the reference XLSX into the test database" do
    batch = BinImport::Importer.new(SOURCE_FILE).call

    assert_equal "validated", batch.status
    assert_equal Date.new(2026, 7, 1), batch.competencia_m1
    assert_equal Date.new(2026, 8, 1), batch.competencia_atual
    assert_equal 24, batch.dia_corte_mes_atual
    assert_equal 457, RevenueSnapshot.count
    assert_equal 94, ActivationProposal.count
    assert_equal 552, MapSnapshot.count
    assert_equal 6807, DailyRevenue.count
    assert_equal 7000, MonthlyVolume.count
    assert_equal 21, DataAnomaly.where(anomaly_type: "ec_duplicate_candidate").count
    assert_equal 1, DataAnomaly.where(anomaly_type: "company_in_multiple_sub_channels").count
    assert_equal 1, DataAnomaly.where(anomaly_type: "row_without_canal").count
    assert_equal 21, ReportScope.new.stalled_companies.size
    assert_equal "45573486000195",
      DataAnomaly.find_by(anomaly_type: "company_in_multiple_sub_channels").company.cnpj

    mapa = MapSnapshot.joins(:establishment).find_by(establishments: { ec: "92540262" })
    assert_equal "MAGAO NA BRASA", mapa.razao_social
    assert_equal "MAGAO NA BRASA COMERCIO E SERVICOS DE AL", mapa.nome_fantasia

    aparecida = ReportScope.new.revenue_by_sub_channel.find do |row|
      row["sub_canal"] == "MIC APARECIDA DE GOIANIA GO 1"
    end
    assert_equal 126_668.29, aparecida["faturamento_m1"].to_d
    assert_equal 75_793.58, aparecida["faturamento_atual"].to_d

    totals = ReportScope.new.totals
    variation = ((totals[:faturamento_atual] / totals[:faturamento_m1] - 1) * 100).round(1)
    assert_equal 5_709_803.00, totals[:faturamento_m1]
    assert_equal 5_580_201.30, totals[:faturamento_atual]
    assert_in_delta(-2.3, variation, 0.1)

    full_previous = DailyRevenueConsolidated.where(competencia: batch.competencia_m1).sum(:amount)
    assert_equal full_previous, totals[:faturamento_m1_cheio]
    naive_variation = ((totals[:faturamento_atual] / full_previous - 1) * 100).round(1)
    assert_in_delta(-24.3, naive_variation, 0.1)
  end

  test "rejects an already imported checksum" do
    BinImport::Importer.new(SOURCE_FILE).call

    error = assert_raises(ArgumentError) { BinImport::Importer.new(SOURCE_FILE).call }
    assert_equal "Arquivo já importado", error.message
  end

  test "rejects divergent headers" do
    path = Rails.root.join("tmp/bad-headers.xlsx")
    Axlsx::Package.new do |package|
      BinImport::Template::SHEETS.each do |sheet|
        package.workbook.add_worksheet(name: sheet) do |worksheet|
          headers = BinImport::Template::EXPECTED_HEADERS.fetch(sheet).dup
          headers[0] = "WRONG" if sheet == "Faturamento"
          worksheet.add_row headers
        end
      end
      package.serialize(path.to_s)
    end

    error = assert_raises(ArgumentError) { BinImport::Importer.new(path).call }
    assert_match(/Cabeçalhos divergentes em Faturamento/, error.message)
  end

  test "a later batch extends coverage without duplicating known days" do
    first = BinImport::Importer.new(SOURCE_FILE).call
    second = ImportBatch.create!(
      channel: first.channel, import_template: first.import_template,
      source_filename: "second.xlsx", file_checksum: "second-batch",
      competencia_m1: first.competencia_m1, competencia_atual: first.competencia_atual,
      dia_corte_mes_atual: 27, status: "pending"
    )
    now = Time.current
    copies = DailyRevenue.where(import_batch: first, competencia: first.competencia_atual).map do |row|
      {
        import_batch_id: second.id, channel_id: row.channel_id, establishment_id: row.establishment_id,
        competencia: row.competencia, day: row.day, amount: row.amount, provisional: row.provisional,
        created_at: now, updated_at: now
      }
    end
    DailyRevenue.insert_all!(copies)
    known = DailyRevenueConsolidated.find_by!(competencia: first.competencia_atual, day: 24)
    establishment = known.establishment
    (25..27).each do |day|
      DailyRevenue.create!(
        import_batch: second, channel: first.channel, establishment:,
        competencia: first.competencia_atual, day:, amount: 10, provisional: true
      )
    end

    BinImport::Consolidator.new(second).call
    coverage = CompetenciaCoverage.find_by(channel: first.channel, competencia: first.competencia_atual)

    assert_equal 27, coverage.max_dia_conhecido
    assert_equal 1, DailyRevenueConsolidated.where(
      establishment:, competencia: first.competencia_atual, day: 24
    ).count
    assert_equal 10, DailyRevenueConsolidated.find_by(
      establishment:, competencia: first.competencia_atual, day: 27
    ).amount
  end
end
