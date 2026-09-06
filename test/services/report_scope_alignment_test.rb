require "test_helper"

class ReportScopeAlignmentTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

  test "alinha dois canais pelo menor dia conhecido" do
    template = BinImport::Template.register!
    seed_channel("A", template, cutoff: 24, amounts: { 24 => 100 }, previous: { 24 => 80, 31 => 40 })
    seed_channel("B", template, cutoff: 27, amounts: { 24 => 100, 27 => 50 }, previous: { 24 => 80, 31 => 40 })
    AuditViews.refresh!

    scope = ReportScope.new
    totals = scope.totals
    rows = scope.revenue_by_sub_channel
    channel_b = Channel.find_by!(external_id: "B")

    assert_equal 24, scope.cutoff_day
    assert scope.mixed_cutoffs?
    assert_equal 200, totals[:current_revenue]
    assert_equal 160, totals[:previous_revenue]
    assert_equal 240, totals[:previous_full_revenue]
    assert_equal 200, rows.sum { |row| row["current_revenue"].to_d }
    assert_equal 160, rows.sum { |row| row["previous_revenue"].to_d }
    assert_equal 240, rows.sum { |row| row["previous_full_revenue"].to_d }
    assert_equal 50, DailyRevenueConsolidated.where(channel: channel_b, day: 27).sum(:amount)

    channel_a = Channel.find_by!(external_id: "A")
    filtered_scope = ReportScope.new(channel_id: channel_a.id)
    assert_equal [ "MIC A" ], filtered_scope.revenue_by_sub_channel.pluck("sub_channel_name")
    assert_equal 100, filtered_scope.totals[:current_revenue]
    assert_equal 80, filtered_scope.totals[:previous_revenue]
    assert_equal 120, filtered_scope.totals[:previous_full_revenue]
  end

  # A regra da comparação alinhada vive em AuditViews e é consumida pela view, pelo total do
  # topo e pela listagem. Se as três não fecharem no mesmo número, a tela mostra um total que
  # nenhuma linha explica.
  test "total do topo, view por subcanal e soma das linhas da listagem fecham no mesmo número" do
    lojas = BinWorkbook.default_lojas
    import_synthetic_workbook(lojas:)
    AuditViews.refresh!
    scope = ReportScope.new
    totals = scope.totals

    rows = SubChannel.pluck(:id).flat_map do |sub_channel_id|
      scope.revenue_by_establishment(sub_channel_id:).rows
    end

    assert_equal soma(lojas, :dias_m1), totals[:previous_full_revenue]
    assert_equal totals[:previous_full_revenue], rows.sum { |row| row["previous_full_revenue"].to_d }
    assert_equal totals[:previous_revenue], rows.sum { |row| row["previous_revenue"].to_d }
    assert_equal totals[:current_revenue], rows.sum { |row| row["current_revenue"].to_d }
    assert_equal totals[:current_revenue],
      scope.revenue_by_sub_channel.sum { |row| row["current_revenue"].to_d }
  end

  # O dashboard agrega daily_revenues_consolidated em toda requisição, e ela só muda numa
  # consolidação ou num ajuste de corte — os dois tocam period_coverages, cujo carimbo vai
  # na chave. Um lote novo, um reprocessamento e um ajuste de corte devem, cada um,
  # derrubar o cache; entre eles, nenhuma requisição volta às tabelas consolidadas.
  test "dashboard fica em cache até a próxima consolidação ou ajuste de corte" do
    lojas = BinWorkbook.default_lojas
    batch = import_synthetic_workbook(lojas:)
    AuditViews.refresh!
    original_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    rows = ReportScope.new.revenue_by_sub_channel
    totals = ReportScope.new.totals
    assert_no_queries_match(/daily_revenues_consolidated/) do
      assert_equal rows, ReportScope.new.revenue_by_sub_channel
      assert_equal totals, ReportScope.new.totals
    end

    Operations::ReprocessBatch.call(batch)
    assert_queries_match(/daily_revenues_consolidated/) { ReportScope.new.revenue_by_sub_channel }
    assert_queries_match(/daily_revenues_consolidated/) { ReportScope.new.totals }

    Operations::AdjustCutoff.call(batch:, max_known_day: 3)
    assert_equal 3, ReportScope.new.revenue_by_sub_channel.first["max_known_day"].to_i
    assert_queries_match(/daily_revenues_consolidated/) { ReportScope.new.totals }

    lojas.first.dias_atual = lojas.first.dias_atual.merge(1 => 999)
    import_synthetic_workbook(lojas:, filename: "BIN_TESTE_20260818.xlsx")
    assert_queries_match(/daily_revenues_consolidated/) { ReportScope.new.revenue_by_sub_channel }
    assert_equal soma(lojas, :dias_atual), ReportScope.new.totals[:current_revenue]
  ensure
    Rails.cache = original_store
  end

  private

  def soma(lojas, campo)
    lojas.sum { |loja| loja.public_send(campo).values.sum }.to_d
  end

  def seed_channel(external_id, template, cutoff:, amounts:, previous: {})
    channel = Channel.create!(external_id:, name: "CANAL #{external_id}")
    company = Company.create!(cnpj: external_id == "A" ? "12345678000191" : "12345678000192")
    establishment = Establishment.create!(
      ec: external_id == "A" ? "11111111" : "22222222",
      company:,
      channel:
    )
    sub_channel = channel.sub_channels.create!(name: "MIC #{external_id}")
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "#{external_id}.xlsx",
      file_checksum: "checksum-#{external_id}", previous_period: Date.new(2026, 7, 1),
      current_period: Date.new(2026, 8, 1), current_month_cutoff_day: cutoff, status: "validated"
    )
    RevenueSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      previous_month_total: previous.values.sum, current_month_total: amounts.values.sum
    )
    now = Time.current
    PeriodCoverage.upsert_all(
      [
        {
          channel_id: channel.id, period: Date.new(2026, 7, 1), max_known_day: 31, closed: true,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        },
        {
          channel_id: channel.id, period: Date.new(2026, 8, 1), max_known_day: cutoff, closed: false,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        }
      ],
      unique_by: "index_period_coverages_on_channel_id_and_period"
    )
    rows = amounts.map do |day, amount|
      {
        establishment_id: establishment.id, channel_id: channel.id, period: Date.new(2026, 8, 1),
        day:, amount:, provisional: true, source_import_batch_id: batch.id, revised_count: 0,
        created_at: now, updated_at: now
      }
    end
    rows.concat(
      previous.map do |day, amount|
        {
          establishment_id: establishment.id, channel_id: channel.id, period: Date.new(2026, 7, 1),
          day:, amount:, provisional: false, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        }
      end
    )
    DailyRevenueConsolidated.upsert_all(rows, unique_by: "index_daily_revenues_consolidated_primary")
    channel
  end
end
