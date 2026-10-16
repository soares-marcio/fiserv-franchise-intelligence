require "test_helper"

# O caso de 13/10/2026: a Região Goiás (REPORT_ID 719) foi lida como Master, mas era um MIC
# de Ramos e Silva (1478), e o arquivo novo do MIC veio sob o 1478 — recusado por "EC de
# outro canal". Juntar é o que deixa o arquivo entrar sem perder a história.
class Operations::MergeChannelTest < ActiveSupport::TestCase
  setup do
    @target = import_synthetic_workbook(stores: BinWorkbook.default_stores.first(2),
      channel: "MASTER RAMOS", report_id: "1478", filename: "BIN_RAMOS_20260811.xlsx").channel
    @source = import_synthetic_workbook(stores: [ gama_store ],
      channel: "MASTER REGIAO", report_id: "719", filename: "BIN_REGIAO_20260811.xlsx").channel
    refresh_audit_views
  end

  test "os ECs, o faturamento e o MIC passam para o destino, e a origem fica apagada" do
    revenue_before = DailyRevenueConsolidated.sum(:amount)

    counts = Operations::MergeChannel.call(source: @source, target: @target, actor: admin_user)

    assert_equal({ "ecs" => 1, "lotes" => 1 }, counts)
    assert @source.reload.deleted?
    assert_equal @target, Establishment.find_by!(ec: "30000003").channel
    assert_equal [ "MIC ALFA", "MIC GAMA" ], @target.sub_channels.active.order(:name).pluck(:name)
    assert_equal revenue_before, DailyRevenueConsolidated.where(channel: @target).sum(:amount),
      "nenhum real de faturamento fica para trás"
    assert_equal({ "MIC ALFA" => 2, "MIC GAMA" => 1 }, view_establishments(@target))
    assert_equal 0, rows_left_in_source, "nada além da trilha aponta para a origem"
    assert AuditEvent.exists?(action: "channel.merged", channel_id: @target.id)
  end

  test "depois de juntar, o arquivo do MIC sob o REPORT_ID do destino entra direto" do
    Operations::MergeChannel.call(source: @source, target: @target, actor: admin_user)
    newer_gama = gama_store.class.new(**gama_store.to_h.merge(current_days: { 1 => 120, 2 => 30 }))

    batch = import_synthetic_workbook(stores: [ newer_gama ], channel: "MASTER RAMOS", report_id: "1478",
      filename: "BIN_GAMA_20260812.xlsx")
    refresh_audit_views

    assert batch.validated?, "sem recusa por EC de outro canal e sem quarentena"
    assert_equal({ "MIC ALFA" => 2, "MIC GAMA" => 1 }, view_establishments(@target))
  end

  test "a cobertura do destino fica com o maior dia conhecido entre os dois" do
    period = Date.new(2026, 8, 1)
    PeriodCoverage.where(channel: @source, period:).update_all(max_known_day: 20)

    Operations::MergeChannel.call(source: @source, target: @target, actor: admin_user)

    assert_equal 20, PeriodCoverage.find_by!(channel: @target, period:).max_known_day
    assert_not PeriodCoverage.exists?(channel_id: @source.id)
  end

  test "quem tinha a origem inteira passa a ter o MIC dela no destino" do
    user = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @source)

    Operations::MergeChannel.call(source: @source, target: @target, actor: admin_user)

    gama = @target.sub_channels.active.find_by!(name: "MIC GAMA")
    assert_equal [ [ @target.id, gama.id ] ], user.access_grants.reload.pluck(:channel_id, :sub_channel_id)
  end

  test "recusa juntar com arquivo em revisão, e juntar um Master nele mesmo" do
    ImportBatch.create!(organization: default_organization, channel: @source, status: "pending_review",
      source_filename: "pendente.xlsx", file_checksum: "pendente")

    actor = admin_user
    assert_raises(ArgumentError) { Operations::MergeChannel.call(source: @source, target: @target, actor:) }
    assert_raises(ArgumentError) { Operations::MergeChannel.call(source: @target, target: @target, actor:) }
    assert_not @source.reload.deleted?
  end

  private

  def gama_store
    BinWorkbook::Store.new(
      ec: "30000003", cnpj: "55666777000188", sub_channel_name: "MIC GAMA",
      legal_name: "GAMA COMERCIO LTDA", trade_name: "GAMA LOJA", contract_status: "Active",
      previous_days: { 1 => 300 }, current_days: { 1 => 120 }, best_conversation: nil, proposal: false
    )
  end

  def view_establishments(channel)
    ApplicationRecord.connection.select_rows(
      "SELECT sub_channel_name, primary_establishments FROM audit_revenue_by_sub_channel WHERE channel_id = #{channel.id}"
    ).to_h { |name, count| [ name, count.to_i ] }
  end

  def rows_left_in_source
    tables = Operations::MergeChannel::SUB_CHANNEL_TABLES + Operations::MergeChannel::CHANNEL_TABLES +
      %w[period_coverages data_anomalies access_grants]
    tables.sum do |table|
      ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM #{table} WHERE channel_id = #{@source.id}").to_i
    end
  end
end
