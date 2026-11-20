require "test_helper"

# A carteira vigente com o Master em mais de um arquivo: a Fiserv passou a mandar a carteira
# de um Master em dois arquivos (um com parte dos MICs, outro com o resto), e o lote vigente
# deixou de ser o do Master para ser o de cada MIC (AuditViews.current_snapshots_sql).
class CurrentPortfolioTest < ActiveSupport::TestCase
  test "dois arquivos do mesmo Master somam os MICs, em vez de um apagar o outro" do
    import_and_approve(stores: alfa_stores, filename: "BIN_ALFA_20260811.xlsx")
    import_and_approve(stores: [ gama_store ], filename: "BIN_GAMA_20260811.xlsx")
    refresh_audit_views

    assert_equal [ %w[30000001 MIC\ ALFA], %w[30000003 MIC\ GAMA], %w[90000001 MIC\ ALFA] ],
      current_ecs("revenue_snapshots")
    assert_equal current_ecs("revenue_snapshots"), current_ecs("map_snapshots")
    assert_equal({ "MIC ALFA" => 2, "MIC GAMA" => 1 }, view_establishments)
  end

  test "EC que muda de MIC entre arquivos conta uma vez só, no MIC do arquivo mais novo" do
    import_synthetic_workbook
    moved = BinWorkbook.default_stores.first
    import_and_approve(stores: [ store_like(moved, sub_channel_name: "MIC GAMA") ],
      filename: "BIN_MUDA_20260812.xlsx")
    refresh_audit_views

    assert_equal [ %w[30000001 MIC\ GAMA], %w[30000002 MIC\ BETA], %w[90000001 MIC\ ALFA] ],
      current_ecs("revenue_snapshots")
    assert_equal({ "MIC ALFA" => 1, "MIC BETA" => 1, "MIC GAMA" => 1 }, view_establishments)
  end

  test "EC que o arquivo novo do MIC não traz sai da carteira, e os outros MICs ficam" do
    import_synthetic_workbook
    import_and_approve(stores: BinWorkbook.default_stores.first(1), filename: "BIN_SAI_20260812.xlsx")

    assert_equal [ %w[30000001 MIC\ ALFA], %w[30000002 MIC\ BETA] ], current_ecs("revenue_snapshots")
  end

  test "cadastro manual de um EC não esconde os outros ECs do MIC" do
    import_synthetic_workbook
    Operations::RegisterManually.call(
      "organization" => default_organization, "report_id" => BinWorkbook::REPORT_ID,
      "channel_name" => BinWorkbook::CHANNEL, "sub_channel_name" => "MIC ALFA",
      "ec" => "12345678", "cnpj" => "12345678000195", "contract_status" => "Active",
      "legal_name" => "RAZAO", "trade_name" => "FANTASIA",
      "previous_period" => "2026-07-01", "current_period" => "2026-08-01",
      "current_month_total" => "100", "day_01" => "100"
    )

    assert_equal [ %w[12345678 MIC\ ALFA], %w[30000001 MIC\ ALFA], %w[30000002 MIC\ BETA],
      %w[90000001 MIC\ ALFA] ], current_ecs("revenue_snapshots")
  end

  test "a competência passada fica com os MICs que cada arquivo dela trouxe" do
    import_and_approve(stores: alfa_stores, filename: "BIN_ALFA_20260811.xlsx")
    import_and_approve(stores: [ gama_store ], filename: "BIN_GAMA_20260811.xlsx")

    periods = ApplicationRecord.connection.select_rows(<<~SQL).map { |ec, period| [ ec, period.to_s ] }.sort
      WITH #{AuditViews.current_snapshots_sql(table: "map_snapshots", by_period: true).strip}
      SELECT establishment.ec, current.current_period
      FROM current_snapshots current
      JOIN map_snapshots snapshot ON snapshot.id = current.id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
    SQL

    assert_equal [ %w[30000001 2026-08-01], %w[30000003 2026-08-01], %w[90000001 2026-08-01] ], periods
  end

  test "recorrência e 3M enxergam os MICs dos dois arquivos" do
    import_and_approve(stores: alfa_stores, filename: "BIN_ALFA_20260811.xlsx")
    import_and_approve(stores: [ gama_store ], filename: "BIN_GAMA_20260811.xlsx")
    refresh_audit_views
    scope = organization_scope

    recurring = RecurringEarningsQuery.new(scope:).by_sub_channel.map { |row| row[:name] }
    periods = [ Date.new(2026, 6, 1), Date.new(2026, 7, 1), Date.new(2026, 8, 1) ]
    earnings = ThreeMonthEarningsQuery.new(periods:, scope:).by_sub_channel.map { |row| row[:name] }

    assert_equal [ "MIC ALFA", "MIC GAMA" ], recurring.sort
    assert_equal [ "MIC ALFA", "MIC GAMA" ], earnings.sort
  end

  test "MIC de arquivo que corta antes é comparado até o próprio corte, e o total até o menor" do
    import_and_approve(stores: alfa_stores, filename: "BIN_ALFA_20260811.xlsx")
    later_gama = store_like(gama_store, current_days: { 1 => 120, 13 => 50 })
    import_and_approve(stores: [ later_gama ], filename: "BIN_GAMA_20260814.xlsx")
    refresh_audit_views

    cutoffs = ApplicationRecord.connection.select_rows(
      "SELECT sub_channel_name, max_known_day FROM audit_revenue_by_sub_channel"
    ).to_h { |name, day| [ name, day.to_i ] }
    report = ReportScope.new(scope: organization_scope)

    assert_equal({ "MIC ALFA" => 10, "MIC GAMA" => 13 }, cutoffs)
    assert_equal 10, report.cutoff_day, "o total não compara dias que um dos arquivos não trouxe"
    assert_equal 13, PeriodCoverage.find_by!(period: Date.new(2026, 8, 1)).max_known_day,
      "a cobertura guardada do Master continua sendo a maior conhecida"
  end

  # O seletor de corte: com os MICs em dias diferentes dentro do mesmo Master, o menor corte
  # esconde os dias que o arquivo adiantado já trouxe. "Cada MIC até o seu" mostra esses dias
  # sem cortar o MIC atrasado num dia que ele não tem.
  test "corte por MIC leva cada MIC até o próprio dia e o total soma as linhas" do
    import_and_approve(stores: alfa_stores, filename: "BIN_ALFA_20260811.xlsx")
    later_gama = store_like(gama_store, current_days: { 1 => 120, 13 => 50 })
    import_and_approve(stores: [ later_gama ], filename: "BIN_GAMA_20260814.xlsx")
    refresh_audit_views

    single = ReportScope.new(scope: organization_scope)
    per_mic = ReportScope.new(scope: organization_scope, cutoff_mode: :per_sub_channel)
    by_name = ->(report) { report.revenue_by_sub_channel.index_by { |row| row["sub_channel_name"] } }

    assert single.mixed_cutoffs?, "o mesmo Master com MICs em dias diferentes é divergência"
    assert_equal [ [ "MIC GAMA", 13 ], [ "MIC ALFA", 10 ] ], single.sub_channel_cutoffs
    assert_equal [ 10, 13 ], [ single.cutoff_day, single.max_cutoff_day ]

    assert_equal [ 10, 10 ], by_name.(single).values_at("MIC ALFA", "MIC GAMA").map { |row| row["max_known_day"].to_i }
    assert_equal [ 10, 13 ], by_name.(per_mic).values_at("MIC ALFA", "MIC GAMA").map { |row| row["max_known_day"].to_i }
    assert_equal 120, by_name.(single)["MIC GAMA"]["current_revenue"].to_d
    assert_equal 170, by_name.(per_mic)["MIC GAMA"]["current_revenue"].to_d, "o dia 13 do GAMA entra"
    assert_equal by_name.(single)["MIC ALFA"].except("max_known_day"), by_name.(per_mic)["MIC ALFA"].except("max_known_day"),
      "o MIC atrasado fica igual nos dois cortes"

    totals = per_mic.totals
    rows = per_mic.revenue_by_sub_channel
    assert_equal rows.sum { |row| row["current_revenue"].to_d }, totals[:current_revenue]
    assert_equal rows.sum { |row| row["previous_revenue"].to_d }, totals[:previous_revenue]
    assert_equal single.totals[:current_revenue] + 50, totals[:current_revenue]
    assert_equal single.totals[:previous_full_revenue], totals[:previous_full_revenue]
  end

  test "sem divergência entre MICs não há corte a escolher" do
    import_and_approve(stores: alfa_stores, filename: "BIN_ALFA_20260811.xlsx")
    same_day_gama = store_like(gama_store, current_days: { 1 => 120, 10 => 50 })
    import_and_approve(stores: [ same_day_gama ], filename: "BIN_GAMA_20260814.xlsx")
    refresh_audit_views

    single = ReportScope.new(scope: organization_scope)
    per_mic = ReportScope.new(scope: organization_scope, cutoff_mode: :per_sub_channel)

    assert_not single.mixed_cutoffs?
    assert_equal single.totals, per_mic.totals
    assert_equal :min, ReportScope.new(scope: organization_scope, cutoff_mode: :qualquer).cutoff_mode
  end

  test "arquivo de outro MIC que corta antes não é anomalia de cobertura; o do mesmo MIC é" do
    later_gama = store_like(gama_store, current_days: { 1 => 120, 13 => 50 })
    import_and_approve(stores: [ later_gama ], filename: "BIN_GAMA_20260814.xlsx")
    import_and_approve(stores: alfa_stores, filename: "BIN_ALFA_20260811.xlsx")

    assert_not DataAnomaly.exists?(anomaly_type: "batch_covers_fewer_days")

    shorter_alfa = alfa_stores.map { |store| store_like(store, current_days: { 1 => 15, 2 => 25 }) }
    import_and_approve(stores: shorter_alfa, filename: "BIN_ALFA_20260803.xlsx")

    assert DataAnomaly.exists?(anomaly_type: "batch_covers_fewer_days")
  end

  private

  def alfa_stores = BinWorkbook.default_stores.first(2)

  def gama_store
    BinWorkbook::Store.new(
      ec: "30000003", cnpj: "55666777000188", sub_channel_name: "MIC GAMA",
      legal_name: "GAMA COMERCIO LTDA", trade_name: "GAMA LOJA", contract_status: "Active",
      previous_days: { 1 => 300 }, current_days: { 1 => 120 }, best_conversation: nil, proposal: false
    )
  end

  def store_like(store, **changes) = store.class.new(**store.to_h.merge(changes))

  # O arquivo parcial para em revisão enquanto a revisão comparar o Master inteiro; aqui o
  # assunto é a leitura depois de aprovado, então aprova.
  def import_and_approve(stores:, filename:)
    batch = import_synthetic_workbook(stores:, filename:)
    return batch unless batch.pending_review?

    Operations::ReviewBatch.approve(batch:, reviewer: admin_user, note: "Arquivo de parte dos MICs")
    batch.reload
  end

  def current_ecs(table)
    ApplicationRecord.connection.select_rows(<<~SQL).sort
      WITH #{AuditViews.current_snapshots_sql(table:).strip}
      SELECT establishment.ec, sub_channel.name
      FROM #{table} snapshot
      JOIN current_snapshots current ON current.id = snapshot.id
      JOIN establishments establishment ON establishment.id = snapshot.establishment_id
      JOIN sub_channels sub_channel ON sub_channel.id = snapshot.sub_channel_id
    SQL
  end

  def view_establishments
    ApplicationRecord.connection.select_rows(
      "SELECT sub_channel_name, primary_establishments FROM audit_revenue_by_sub_channel"
    ).to_h { |name, count| [ name, count.to_i ] }
  end
end
