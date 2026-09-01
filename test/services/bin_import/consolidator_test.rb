require "test_helper"

class BinImport::ConsolidatorTest < ActiveSupport::TestCase
  setup do
    @primeiro = import_synthetic_workbook
    @loja = BinWorkbook.default_lojas.first
    @establishment = Establishment.find_by!(ec: @loja.ec)
  end

  test "consolida um dia por estabelecimento e competência" do
    esperado = BinWorkbook.default_lojas.sum { |loja| loja.dias_m1.size + loja.dias_atual.size }

    assert_equal esperado, DailyRevenueConsolidated.count
    assert_equal @loja.dias_m1.fetch(1), DailyRevenueConsolidated.find_by!(
      establishment: @establishment, period: @primeiro.previous_period, day: 1
    ).amount
  end

  test "registra revisão quando um dia já conhecido muda de valor" do
    revisadas = BinWorkbook.default_lojas
    revisadas.first.dias_m1 = revisadas.first.dias_m1.merge(1 => 150)
    import_synthetic_workbook(lojas: revisadas, filename: "BIN_TESTE_20260812.xlsx")

    revisao = DailyRevenueRevision.find_by!(
      establishment_id: @establishment.id, period: @primeiro.previous_period, day: 1
    )
    assert_equal @loja.dias_m1.fetch(1), revisao.previous_amount
    assert_equal 150, revisao.new_amount
    assert_equal 150, DailyRevenueConsolidated.find_by!(
      establishment: @establishment, period: @primeiro.previous_period, day: 1
    ).amount
  end

  test "aponta revisão de competência já fechada" do
    revisadas = BinWorkbook.default_lojas
    revisadas.first.dias_m1 = revisadas.first.dias_m1.merge(1 => 150)
    import_synthetic_workbook(lojas: revisadas, filename: "BIN_TESTE_20260812.xlsx")

    anomalia = DataAnomaly.find_by(anomaly_type: "closed_period_revised")
    assert anomalia, "mudança em mês fechado precisa virar anomalia"
    assert_equal "atencao", anomalia.severity
    assert_equal @primeiro.previous_period.to_s, anomalia.details["period"]
  end

  test "não regride a cobertura quando o lote novo cobre menos dias" do
    curtas = BinWorkbook.default_lojas
    curtas.each { |loja| loja.dias_atual = loja.dias_atual.reject { |day, _| day > 2 } }
    import_synthetic_workbook(lojas: curtas, filename: "BIN_TESTE_20260805.xlsx")

    coverage = PeriodCoverage.find_by!(
      channel_id: @primeiro.channel_id, period: @primeiro.current_period
    )
    assert_equal BinWorkbook.cutoff_day, coverage.max_known_day
    assert DataAnomaly.find_by(anomaly_type: "batch_covers_fewer_days"),
      "lote mais curto precisa ser registrado"
  end

  test "marca o mês anterior como fechado e o atual como aberto" do
    coberturas = PeriodCoverage.where(channel_id: @primeiro.channel_id).index_by(&:period)

    assert coberturas.fetch(@primeiro.previous_period).closed
    assert_equal 31, coberturas.fetch(@primeiro.previous_period).max_known_day
    assert_not coberturas.fetch(@primeiro.current_period).closed
    assert_equal BinWorkbook.cutoff_day, coberturas.fetch(@primeiro.current_period).max_known_day
  end

  test "consolida os volumes mensais de todas as competências do arquivo" do
    esperado = BinWorkbook.default_lojas.size *
      BinImport::Template::VOLUME_FAMILIES.size * BinImport::Template::DEFAULT_VOLUME_MONTHS.size

    assert_equal esperado, MonthlyVolumeConsolidated.count
  end
end
