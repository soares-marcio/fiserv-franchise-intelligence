require "test_helper"

class ReportScopeEstablishmentsTest < ActiveSupport::TestCase
  test "monta totais comparáveis por estabelecimento a partir dos valores diários conhecidos" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    other = channel.sub_channels.find_by!(name: "MIC B")
    AuditViews.refresh!

    scope = ReportScope.new
    rows = scope.revenue_by_establishment(sub_channel_id: sub_channel.id)
    parent = scope.revenue_by_sub_channel.find { |row| row["sub_channel_id"] == sub_channel.id }

    assert_equal [ "11111111", "22222222" ], rows.map { |row| row["ec"] }
    assert_equal "12345678000191", rows.first["cnpj"]
    assert_equal "LOJA UM", rows.first["trade_name"]
    assert_equal "LOJA UM LTDA", rows.first["legal_name"]
    assert_equal "Active", rows.first["contract_status"]
    assert_equal Date.new(2024, 3, 15), rows.first["accredited_on"]
    assert_equal Date.new(2024, 4, 2), rows.first["activated_on"]
    assert_nil rows.first["suspended_on"]

    first = rows.find { |row| row["ec"] == "11111111" }
    assert_equal 120, first["previous_full_revenue"].to_d
    assert_equal 80, first["previous_revenue"].to_d
    assert_equal 100, first["current_revenue"].to_d
    assert_equal({ "24" => 80.to_d, "31" => 40.to_d }, stringify_days(first["previous_days"]))
    assert_equal({ "24" => 100.to_d }, stringify_days(first["current_days"]))

    assert_equal parent["previous_full_revenue"].to_d, rows.sum { |row| row["previous_full_revenue"].to_d }
    assert_equal parent["previous_revenue"].to_d, rows.sum { |row| row["previous_revenue"].to_d }
    assert_equal parent["current_revenue"].to_d, rows.sum { |row| row["current_revenue"].to_d }

    other_rows = scope.revenue_by_establishment(sub_channel_id: other.id)
    assert_equal [ "33333333" ], other_rows.map { |row| row["ec"] }
    assert_equal 50, other_rows.first["current_revenue"].to_d
    assert_equal({ "24" => 50.to_d }, stringify_days(other_rows.first["current_days"]))
  end

  test "filtra estabelecimentos por mais de um status de contrato" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    RevenueSnapshot.find_by!(establishment: Establishment.find_by!(ec: "22222222"))
      .update!(contract_status: "Suspended")
    scope = ReportScope.new(channel_id: channel.id)

    active = scope.revenue_by_establishment(sub_channel_id: sub_channel.id, statuses: [ "Active" ])
    both = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, statuses: [ "Active", "Suspended" ]
    )

    assert_equal [ "11111111" ], active.map { |row| row["ec"] }
    assert_equal [ "11111111", "22222222" ], both.map { |row| row["ec"] }
  end

  test "filtra estabelecimentos por datas de credenciamento, ativação e suspensão" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    MapSnapshot.find_by!(establishment: Establishment.find_by!(ec: "22222222"))
      .update!(accredited_on: Date.new(2024, 5, 1), activated_on: nil,
        suspended_on: Date.new(2024, 6, 10))
    scope = ReportScope.new(channel_id: channel.id)

    credentialed = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, date_kinds: [ "credenciamento" ],
      from_date: "2024-03-01", to_date: "2024-03-31"
    )
    suspended = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, date_kinds: [ "suspensao" ],
      from_date: "2024-06-01", to_date: "2024-06-30"
    )
    either = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, date_kinds: [ "ativacao", "suspensao" ],
      from_date: "2024-04-01", to_date: "2024-06-30"
    )
    all_date_kinds = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, from_date: "2024-06-01", to_date: "2024-06-30"
    )

    assert_equal [ "11111111" ], credentialed.map { |row| row["ec"] }
    assert_equal [ "22222222" ], suspended.map { |row| row["ec"] }
    assert_equal [ "11111111", "22222222" ], either.map { |row| row["ec"] }
    assert_equal [ "22222222" ], all_date_kinds.map { |row| row["ec"] }
  end

  test "usa as datas de ciclo de vida do mesmo lote do snapshot de faturamento" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    establishment = Establishment.find_by!(ec: "11111111")
    newer_map_batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "mapa.xlsx",
      file_checksum: "checksum-map", previous_period: Date.new(2026, 7, 1),
      current_period: Date.new(2026, 8, 1), current_month_cutoff_day: 24, status: "validated"
    )
    MapSnapshot.create!(
      import_batch: newer_map_batch, channel:, sub_channel:, establishment:,
      legal_name: "LOJA UM LTDA", trade_name: "LOJA UM", contract_status: "Active",
      accredited_on: Date.new(2025, 1, 10), activated_on: Date.new(2025, 2, 20)
    )

    row = ReportScope.new(channel_id: channel.id)
      .revenue_by_establishment(sub_channel_id: sub_channel.id).first

    assert_equal Date.new(2024, 3, 15), row["accredited_on"]
    assert_equal Date.new(2024, 4, 2), row["activated_on"]
  end

  test "lista os status de contrato só do último lote de faturamento" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    latest_batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "latest.xlsx",
      file_checksum: "checksum-latest", previous_period: Date.new(2026, 7, 1),
      current_period: Date.new(2026, 8, 1), current_month_cutoff_day: 24, status: "validated"
    )
    RevenueSnapshot.create!(
      import_batch: latest_batch, channel:, sub_channel:,
      establishment: Establishment.find_by!(ec: "11111111"),
      legal_name: "LOJA UM LTDA", trade_name: "LOJA UM", contract_status: "Suspended"
    )

    statuses = ReportScope.new(channel_id: channel.id).contract_statuses(sub_channel_id: sub_channel.id)

    assert_equal [ "Suspended" ], statuses
  end

  test "filtra os totais por estabelecimento pelo mês e faixa de dias selecionados" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    scope = ReportScope.new(channel_id: channel.id)

    day_31 = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, from_day: 31, to_day: 31
    ).find { |row| row["ec"] == "11111111" }
    july = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, period: Date.new(2026, 7, 1), from_day: 24, to_day: 24
    ).find { |row| row["ec"] == "11111111" }

    assert_equal 40, day_31["previous_revenue"].to_d
    assert_equal 0, day_31["current_revenue"].to_d
    assert_equal 80, july["current_revenue"].to_d
    assert_equal 0, july["previous_revenue"].to_d
  end

  test "filtra estabelecimentos por nome, EC ou CNPJ" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    scope = ReportScope.new(channel_id: channel.id)

    by_name = scope.revenue_by_establishment(sub_channel_id: sub_channel.id, query: "loja um")
    by_ec = scope.revenue_by_establishment(sub_channel_id: sub_channel.id, query: "22222222")
    by_cnpj = scope.revenue_by_establishment(sub_channel_id: sub_channel.id, query: "12.345.678/0001-91")

    assert_equal [ "11111111" ], by_name.map { |row| row["ec"] }
    assert_equal [ "22222222" ], by_ec.map { |row| row["ec"] }
    assert_equal [ "11111111", "22222222" ], by_cnpj.map { |row| row["ec"] }
  end

  test "pagina estabelecimentos sem encolher os totais da seleção" do
    template = BinImport::Template.register!
    channel = seed_channel(template)
    sub_channel = channel.sub_channels.find_by!(name: "MIC A")
    scope = ReportScope.new(channel_id: channel.id)

    first_page = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, page: 1, per_page: 1
    )
    second_page = scope.revenue_by_establishment(
      sub_channel_id: sub_channel.id, page: 2, per_page: 1
    )

    assert_equal [ "11111111" ], first_page.map { |row| row["ec"] }
    assert_equal [ "22222222" ], second_page.map { |row| row["ec"] }
    assert_equal 2, first_page.total_count
    assert_equal 2, first_page.total_pages
    assert_equal 120 + 20, first_page.totals[:previous_full_revenue]
    assert_equal first_page.totals, second_page.totals
  end

  private

  def stringify_days(payload)
    days = payload.is_a?(String) ? JSON.parse(payload) : payload
    days.to_h { |day, amount| [ day.to_s, amount.to_d ] }
  end

  def seed_channel(template)
    channel = Channel.create!(external_id: "A", name: "CANAL A")
    company = Company.create!(cnpj: "12345678000191")
    other_company = Company.create!(cnpj: "12345678000192")
    first = Establishment.create!(ec: "11111111", company:, channel:)
    second = Establishment.create!(ec: "22222222", company:, channel:)
    outsider = Establishment.create!(ec: "33333333", company: other_company, channel:)
    sub_a = channel.sub_channels.create!(name: "MIC A")
    sub_b = channel.sub_channels.create!(name: "MIC B")
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "a.xlsx",
      file_checksum: "checksum-a", previous_period: Date.new(2026, 7, 1),
      current_period: Date.new(2026, 8, 1), current_month_cutoff_day: 24, status: "validated"
    )
    [
      [ first, sub_a, "LOJA UM LTDA", "LOJA UM", { 24 => 80, 31 => 40 }, { 24 => 100 } ],
      [ second, sub_a, "LOJA DOIS LTDA", "LOJA DOIS", { 24 => 20 }, { 24 => 30 } ],
      [ outsider, sub_b, "OUTRA LTDA", "OUTRA", { 24 => 10 }, { 24 => 50, 27 => 9 } ]
    ].each do |establishment, sub_channel, legal_name, trade_name, previous, current|
      RevenueSnapshot.create!(
        import_batch: batch, channel:, sub_channel:, establishment:,
        legal_name:, trade_name:, contract_status: "Active",
        previous_month_total: previous.values.sum, current_month_total: current.values.sum
      )
      MapSnapshot.create!(
        import_batch: batch, channel:, sub_channel:, establishment:,
        legal_name:, trade_name:, contract_status: "Active",
        accredited_on: Date.new(2024, 3, 15), activated_on: Date.new(2024, 4, 2)
      )
      persist_days(establishment, channel, batch, Date.new(2026, 7, 1), previous, false)
      persist_days(establishment, channel, batch, Date.new(2026, 8, 1), current, true)
    end
    now = Time.current
    PeriodCoverage.upsert_all(
      [
        {
          channel_id: channel.id, period: Date.new(2026, 7, 1), max_known_day: 31, closed: true,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        },
        {
          channel_id: channel.id, period: Date.new(2026, 8, 1), max_known_day: 24, closed: false,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        }
      ],
      unique_by: "index_period_coverages_on_channel_id_and_period"
    )
    channel
  end

  def persist_days(establishment, channel, batch, period, amounts, provisional)
    return if amounts.empty?

    DailyRevenueConsolidated.upsert_all(
      amounts.map do |day, amount|
        {
          establishment_id: establishment.id, channel_id: channel.id, period:,
          day:, amount:, provisional:, source_import_batch_id: batch.id, revised_count: 0,
          created_at: Time.current, updated_at: Time.current
        }
      end,
      unique_by: "index_daily_revenues_consolidated_primary"
    )
  end
end
