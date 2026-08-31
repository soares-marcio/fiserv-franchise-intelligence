require "test_helper"
require "caxlsx"

class BinImport::ImporterTest < ActiveSupport::TestCase
  # A planilha real da Fiserv não é versionada: fica no franchise-storage ao lado do
  # repositório. Quando existe, o teste de referência no fim deste arquivo roda contra ela.
  REFERENCE_FILE = Pathname.new(ENV.fetch("BIN_REFERENCE_FILE", Rails.root.join(
    "../franchise-storage/storage/1478_MASTER_FRANQUEADO_RAMOS_E_SILVA_20260825.xlsx"
  ).to_s))

  setup do
    @lojas = BinWorkbook.default_lojas
    @cutoff = BinWorkbook.cutoff_day(@lojas)
  end

  test "importa a planilha sintética e reconcilia as competências" do
    batch = import_synthetic_workbook(lojas: @lojas)

    assert_equal "validated", batch.status
    assert_equal BinWorkbook::COMPETENCIA_M1, batch.previous_period
    assert_equal BinWorkbook::COMPETENCIA_ATUAL, batch.current_period
    assert_equal @cutoff, batch.current_month_cutoff_day
    assert_equal @lojas.size, MapSnapshot.count
    assert_equal @lojas.size, RevenueSnapshot.count
    assert_equal @lojas.count(&:proposta), ActivationProposal.count
    assert_equal lancamentos_esperados, DailyRevenue.count
    assert_equal volumes_esperados, MonthlyVolume.count
  end

  test "grava os totais mensais da aba Faturamento no snapshot" do
    import_synthetic_workbook(lojas: @lojas)
    loja = @lojas.first
    snapshot = RevenueSnapshot.joins(:establishment).find_by!(establishments: { ec: loja.ec })

    assert_equal loja.total_m1, snapshot.previous_month_total
    assert_equal loja.total_atual, snapshot.current_month_total
  end

  test "grava razão social e nome fantasia nos campos certos nas três abas" do
    import_synthetic_workbook(lojas: @lojas)
    loja = @lojas.first

    mapa = MapSnapshot.joins(:establishment).find_by!(establishments: { ec: loja.ec })
    faturamento = RevenueSnapshot.joins(:establishment).find_by!(establishments: { ec: loja.ec })
    ativacao = ActivationProposal.joins(:establishment).find_by!(establishments: { ec: loja.ec })

    [ mapa, faturamento, ativacao ].each do |registro|
      assert_equal loja.legal_name, registro.legal_name, "#{registro.class}: razão social"
      assert_equal loja.trade_name, registro.trade_name, "#{registro.class}: nome fantasia"
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

    coverage = PeriodCoverage.find_by!(channel: first.channel, period: first.current_period)
    establishment = Establishment.find_by!(ec: estendidas.first.ec)

    assert_equal 12, coverage.max_known_day
    assert_equal 1, DailyRevenueConsolidated.where(
      establishment:, period: first.current_period, day: 10
    ).count
    assert_equal 60, DailyRevenueConsolidated.find_by!(
      establishment:, period: first.current_period, day: 12
    ).amount
  end

  test "arquivo de referência da Fiserv, quando presente no disco" do
    skip "planilha de referência não está no disco" unless File.exist?(REFERENCE_FILE)

    batch = BinImport::Importer.new(REFERENCE_FILE).call

    assert_equal "validated", batch.status
    assert_equal Date.new(2026, 7, 1), batch.previous_period
    assert_equal Date.new(2026, 8, 1), batch.current_period
    assert_equal 24, batch.current_month_cutoff_day
    assert_equal 457, RevenueSnapshot.count
    assert_equal 552, MapSnapshot.count

    mapa = MapSnapshot.joins(:establishment).find_by!(establishments: { ec: "92540262" })
    assert_equal "MAGAO NA BRASA COMERCIO E SERVICOS DE AL", mapa.legal_name
    assert_equal "MAGAO NA BRASA", mapa.trade_name
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
