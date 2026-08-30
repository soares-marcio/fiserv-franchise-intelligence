require "test_helper"
require "caxlsx"

class BinImport::ImporterTest < ActiveSupport::TestCase
  # A planilha real da Fiserv não é versionada; quando ela existe localmente,
  # o teste de referência no fim deste arquivo roda contra ela.
  REFERENCE_FILE = Rails.root.join("1478_MASTER_FRANQUEADO_RAMOS_E_SILVA_20260825.xlsx")

  setup do
    @lojas = BinWorkbook.default_lojas
    @cutoff = BinWorkbook.cutoff_day(@lojas)
  end

  test "importa a planilha sintética e reconcilia as competências" do
    batch = import_synthetic_workbook(lojas: @lojas)

    assert_equal "validated", batch.status
    assert_equal BinWorkbook::COMPETENCIA_M1, batch.competencia_m1
    assert_equal BinWorkbook::COMPETENCIA_ATUAL, batch.competencia_atual
    assert_equal @cutoff, batch.dia_corte_mes_atual
    assert_equal @lojas.size, MapSnapshot.count
    assert_equal @lojas.size, RevenueSnapshot.count
    assert_equal @lojas.count(&:proposta), ActivationProposal.count
    assert_equal lancamentos_esperados, DailyRevenue.count
    assert_equal volumes_esperados, MonthlyVolume.count
  end

  test "grava razão social e nome fantasia nos campos certos nas três abas" do
    import_synthetic_workbook(lojas: @lojas)
    loja = @lojas.first

    mapa = MapSnapshot.joins(:establishment).find_by!(establishments: { ec: loja.ec })
    faturamento = RevenueSnapshot.joins(:establishment).find_by!(establishments: { ec: loja.ec })
    ativacao = ActivationProposal.joins(:establishment).find_by!(establishments: { ec: loja.ec })

    [ mapa, faturamento, ativacao ].each do |registro|
      assert_equal loja.razao_social, registro.razao_social, "#{registro.class}: razão social"
      assert_equal loja.nome_fantasia, registro.nome_fantasia, "#{registro.class}: nome fantasia"
    end
  end

  test "o mês anterior cheio ignora o corte e o comparável respeita" do
    import_synthetic_workbook(lojas: @lojas)
    totals = ReportScope.new.totals

    assert_equal soma(@lojas, :dias_m1), totals[:faturamento_m1_cheio]
    assert_equal soma(@lojas, :dias_m1, ate: @cutoff), totals[:faturamento_m1]
    assert_equal soma(@lojas, :dias_atual, ate: @cutoff), totals[:faturamento_atual]
    assert_operator totals[:faturamento_m1_cheio], :>, totals[:faturamento_m1]
  end

  test "detecta EC 3xx duplicado do 9xx do mesmo CNPJ" do
    batch = import_synthetic_workbook(lojas: @lojas)
    anomalia = DataAnomaly.find_by(anomaly_type: "ec_duplicate_candidate")

    assert_equal batch.channel_id, anomalia.channel_id
    assert_equal "30000001", anomalia.establishment.ec
    assert_equal "90000001", anomalia.details["paired_ec"]
  end

  test "recusa a mesma planilha duas vezes pelo checksum" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-BIN_TESTE_20260811.xlsx")
    BinWorkbook.write(path, lojas: @lojas)
    BinImport::Importer.new(path, source_filename: "BIN_TESTE_20260811.xlsx").call

    error = assert_raises(ArgumentError) do
      BinImport::Importer.new(path, source_filename: "BIN_TESTE_20260811.xlsx").call
    end
    assert_equal "Arquivo já importado", error.message
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "recusa cabeçalhos divergentes" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-bad-headers.xlsx")
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
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "recusa EC que muda de CNPJ entre importações" do
    import_synthetic_workbook(lojas: @lojas)
    outras = BinWorkbook.default_lojas
    outras.first.cnpj = "99888777000166"

    error = assert_raises(ArgumentError) { import_synthetic_workbook(lojas: outras) }
    assert_equal "EC 30000001 mudou de CNPJ", error.message
  end

  test "um lote posterior estende a cobertura sem duplicar dias conhecidos" do
    first = import_synthetic_workbook(lojas: @lojas)
    estendidas = BinWorkbook.default_lojas
    estendidas.first.dias_atual = estendidas.first.dias_atual.merge(11 => 90, 12 => 60)
    second = import_synthetic_workbook(lojas: estendidas, filename: "BIN_TESTE_20260813.xlsx")

    coverage = CompetenciaCoverage.find_by!(channel: first.channel, competencia: first.competencia_atual)
    establishment = Establishment.find_by!(ec: estendidas.first.ec)

    assert_equal 12, coverage.max_dia_conhecido
    assert_equal 1, DailyRevenueConsolidated.where(
      establishment:, competencia: first.competencia_atual, day: 10
    ).count
    assert_equal 60, DailyRevenueConsolidated.find_by!(
      establishment:, competencia: first.competencia_atual, day: 12
    ).amount
  end

  test "arquivo de referência da Fiserv, quando presente no disco" do
    skip "planilha de referência não está no disco" unless File.exist?(REFERENCE_FILE)

    batch = BinImport::Importer.new(REFERENCE_FILE).call

    assert_equal "validated", batch.status
    assert_equal Date.new(2026, 7, 1), batch.competencia_m1
    assert_equal Date.new(2026, 8, 1), batch.competencia_atual
    assert_equal 24, batch.dia_corte_mes_atual
    assert_equal 457, RevenueSnapshot.count
    assert_equal 552, MapSnapshot.count

    mapa = MapSnapshot.joins(:establishment).find_by!(establishments: { ec: "92540262" })
    assert_equal "MAGAO NA BRASA COMERCIO E SERVICOS DE AL", mapa.razao_social
    assert_equal "MAGAO NA BRASA", mapa.nome_fantasia
  end

  private

  def soma(lojas, campo, ate: nil)
    lojas.sum do |loja|
      loja.public_send(campo).sum { |day, amount| ate && day > ate ? 0 : amount }
    end.to_d
  end

  def lancamentos_esperados
    @lojas.sum { |loja| loja.dias_m1.size + loja.dias_atual.size }
  end

  def volumes_esperados
    @lojas.size * BinImport::Template::VOLUME_FAMILIES.size * BinImport::Template::VOLUME_MONTHS.size
  end
end
