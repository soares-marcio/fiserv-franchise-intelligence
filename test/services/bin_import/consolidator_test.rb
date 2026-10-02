require "test_helper"

class BinImport::ConsolidatorTest < ActiveSupport::TestCase
  setup do
    @first_item = import_synthetic_workbook
    @store = BinWorkbook.default_stores.first
    @establishment = Establishment.find_by!(ec: @store.ec)
  end

  test "consolida um dia por estabelecimento e competência" do
    expected = BinWorkbook.default_stores.sum { |store| store.previous_days.size + store.current_days.size }

    assert_equal expected, DailyRevenueConsolidated.count
    assert_equal @store.previous_days.fetch(1), DailyRevenueConsolidated.find_by!(
      establishment: @establishment, period: @first_item.previous_period, day: 1
    ).amount
  end

  test "registra revisão quando um dia já conhecido muda de valor" do
    reviewed = BinWorkbook.default_stores
    reviewed.first.previous_days = reviewed.first.previous_days.merge(1 => 150)
    import_synthetic_workbook(stores: reviewed, filename: "BIN_TESTE_20260812.xlsx")

    review = DailyRevenueRevision.find_by!(
      establishment_id: @establishment.id, period: @first_item.previous_period, day: 1
    )
    assert_equal @store.previous_days.fetch(1), review.previous_amount
    assert_equal 150, review.new_amount
    assert_equal 150, DailyRevenueConsolidated.find_by!(
      establishment: @establishment, period: @first_item.previous_period, day: 1
    ).amount
  end

  test "aponta revisão de competência já fechada" do
    reviewed = BinWorkbook.default_stores
    reviewed.first.previous_days = reviewed.first.previous_days.merge(1 => 150)
    import_synthetic_workbook(stores: reviewed, filename: "BIN_TESTE_20260812.xlsx")

    anomaly = DataAnomaly.find_by(anomaly_type: "closed_period_revised")
    assert anomaly, "mudança em mês fechado precisa virar anomalia"
    assert_equal "atencao", anomaly.severity
    assert_equal @first_item.previous_period.to_s, anomaly.details["period"]
  end

  test "não regride a cobertura quando o lote novo cobre menos dias" do
    short_ones = BinWorkbook.default_stores
    short_ones.each { |store| store.current_days = store.current_days.reject { |day, _| day > 2 } }
    import_synthetic_workbook(stores: short_ones, filename: "BIN_TESTE_20260805.xlsx")

    coverage = PeriodCoverage.find_by!(
      channel_id: @first_item.channel_id, period: @first_item.current_period
    )
    assert_equal BinWorkbook.cutoff_day, coverage.max_known_day
    assert DataAnomaly.find_by(anomaly_type: "batch_covers_fewer_days"),
      "lote mais curto precisa ser registrado"
  end

  test "marca o mês anterior como fechado e o atual como aberto" do
    coverages = PeriodCoverage.where(channel_id: @first_item.channel_id).index_by(&:period)

    assert coverages.fetch(@first_item.previous_period).closed
    assert_equal 31, coverages.fetch(@first_item.previous_period).max_known_day
    assert_not coverages.fetch(@first_item.current_period).closed
    assert_equal BinWorkbook.cutoff_day, coverages.fetch(@first_item.current_period).max_known_day
  end

  test "consolida os volumes mensais de todas as competências do arquivo" do
    expected = BinWorkbook.default_stores.size *
      BinImport::Template::VOLUME_FAMILIES.size * BinImport::Template::DEFAULT_VOLUME_MONTHS.size

    assert_equal expected, MonthlyVolumeConsolidated.count
  end
end
