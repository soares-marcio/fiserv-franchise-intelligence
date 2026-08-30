require "test_helper"

class ReportScopeAlignmentTest < ActiveSupport::TestCase
  test "aligns two channels by the smallest known day" do
    template = BinImport::Template.register!
    seed_channel("A", template, cutoff: 24, amounts: { 24 => 100 }, previous: { 24 => 80, 31 => 40 })
    seed_channel("B", template, cutoff: 27, amounts: { 24 => 100, 27 => 50 }, previous: { 24 => 80, 31 => 40 })
    AuditViews.refresh!

    scope = ReportScope.new
    totals = scope.aligned_totals
    rows = scope.revenue_by_sub_channel
    channel_b = Channel.find_by!(external_id: "B")

    assert_equal 24, scope.cutoff_day
    assert scope.mixed_cutoffs?
    assert_equal 200, totals[:faturamento_atual]
    assert_equal 160, totals[:faturamento_m1]
    assert_equal 240, totals[:faturamento_m1_cheio]
    assert_equal 200, rows.sum { |row| row["faturamento_atual"].to_d }
    assert_equal 160, rows.sum { |row| row["faturamento_m1"].to_d }
    assert_equal 240, rows.sum { |row| row["faturamento_m1_cheio"].to_d }
    assert_equal 50, DailyRevenueConsolidated.where(channel: channel_b, day: 27).sum(:amount)

    channel_a = Channel.find_by!(external_id: "A")
    filtered_scope = ReportScope.new(channel_id: channel_a.id)
    assert_equal [ "MIC A" ], filtered_scope.revenue_by_sub_channel.pluck("sub_canal")
    assert_equal 100, filtered_scope.totals[:faturamento_atual]
    assert_equal 80, filtered_scope.totals[:faturamento_m1]
    assert_equal 120, filtered_scope.totals[:faturamento_m1_cheio]
  end

  private

  def seed_channel(external_id, template, cutoff:, amounts:, previous: {})
    channel = Channel.create!(external_id:, canal: "CANAL #{external_id}")
    company = Company.create!(cnpj: external_id == "A" ? "12345678000191" : "12345678000192")
    establishment = Establishment.create!(
      ec: external_id == "A" ? "11111111" : "22222222",
      company:,
      channel:
    )
    sub_channel = channel.sub_channels.create!(sub_canal: "MIC #{external_id}")
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "#{external_id}.xlsx",
      file_checksum: "checksum-#{external_id}", competencia_m1: Date.new(2026, 7, 1),
      competencia_atual: Date.new(2026, 8, 1), dia_corte_mes_atual: cutoff, status: "validated"
    )
    RevenueSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      fat_total_m1: previous.values.sum, fat_total_mes_atual: amounts.values.sum
    )
    now = Time.current
    CompetenciaCoverage.upsert_all(
      [
        {
          channel_id: channel.id, competencia: Date.new(2026, 7, 1), max_dia_conhecido: 31, fechado: true,
          ultimo_import_batch_id: batch.id, created_at: now, updated_at: now
        },
        {
          channel_id: channel.id, competencia: Date.new(2026, 8, 1), max_dia_conhecido: cutoff, fechado: false,
          ultimo_import_batch_id: batch.id, created_at: now, updated_at: now
        }
      ],
      unique_by: "index_competencia_coverages_on_channel_id_and_competencia"
    )
    rows = amounts.map do |day, amount|
      {
        establishment_id: establishment.id, channel_id: channel.id, competencia: Date.new(2026, 8, 1),
        day:, amount:, provisional: true, source_import_batch_id: batch.id, revised_count: 0,
        created_at: now, updated_at: now
      }
    end
    rows.concat(
      previous.map do |day, amount|
        {
          establishment_id: establishment.id, channel_id: channel.id, competencia: Date.new(2026, 7, 1),
          day:, amount:, provisional: false, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        }
      end
    )
    DailyRevenueConsolidated.upsert_all(rows, unique_by: "index_daily_revenues_consolidated_primary")
    channel
  end
end
