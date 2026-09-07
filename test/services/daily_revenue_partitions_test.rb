require "test_helper"

# Partição de daily_revenues: precisa existir antes de qualquer insert do mês, e criá-la
# custa um ACCESS EXCLUSIVE na partição default — que bloqueia todo import concorrente.
class DailyRevenuePartitionsTest < ActiveSupport::TestCase
  PERIOD = Date.new(2031, 3, 1)
  PARTITION = "daily_revenues_203103".freeze

  setup do
    @connection = ApplicationRecord.connection
    @connection.execute("DROP TABLE IF EXISTS #{PARTITION}")
  end

  teardown do
    @connection.execute("DROP TABLE IF EXISTS #{PARTITION}")
  end

  test "cria a partição do mês e aceita ser chamada de novo" do
    DailyRevenuePartitions.ensure!(PERIOD)

    assert @connection.table_exists?(PARTITION)
    assert_nothing_raised { DailyRevenuePartitions.ensure!(PERIOD) }
    assert @connection.table_exists?(PARTITION)
  end

  test "a partição criada recebe as linhas do próprio mês" do
    DailyRevenuePartitions.ensure!(PERIOD)
    batch = ImportBatch.validated.first || import_synthetic_workbook
    establishment = Establishment.first

    DailyRevenue.insert_all!([ {
      import_batch_id: batch.id, channel_id: batch.channel_id, establishment_id: establishment.id,
      period: PERIOD, day: 1, amount: 10, provisional: true,
      created_at: Time.current, updated_at: Time.current
    } ])

    assert_equal 1, @connection.select_value("SELECT COUNT(*) FROM #{PARTITION}")
  end

  # Três imports simultâneos disputavam o mesmo ACCESS EXCLUSIVE duas vezes cada, mesmo com
  # a partição já criada — o lock é necessário para criar, nunca para constatar que existe.
  test "não trava a partição default quando a partição do mês já existe" do
    DailyRevenuePartitions.ensure!(PERIOD)

    assert_empty locks_while { DailyRevenuePartitions.ensure!(PERIOD) }
  end

  test "trava a partição default só na criação" do
    assert_equal 1, locks_while { DailyRevenuePartitions.ensure!(PERIOD) }.size
  end

  test "import cujas partições já existem não trava a partição default" do
    lojas = BinWorkbook.default_lojas
    import_synthetic_workbook(lojas:)
    lojas.first.dias_atual = lojas.first.dias_atual.merge(3 => 77)

    locks = locks_while do
      import_synthetic_workbook(lojas:, filename: "BIN_TESTE_20260818.xlsx")
    end

    assert_empty locks
  end

  private

  def locks_while
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] if payload[:sql].match?(/LOCK TABLE daily_revenues_default/)
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
