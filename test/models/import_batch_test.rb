require "test_helper"

# Os predicados do lote governam o que a tela de importação mostra: se o worker está vivo,
# se a carteira está desatualizada, se um lote pode ser descartado ou travou.
class ImportBatchTest < ActiveSupport::TestCase
  test "sem lote validado a carteira está desatualizada e não há idade a mostrar" do
    assert_nil ImportBatch.days_since_last_file
    assert_predicate ImportBatch, :stale?
  end

  test "a idade da carteira conta do último lote validado" do
    batch = import_synthetic_workbook
    batch.update_column(:created_at, 3.days.ago)

    assert_equal 3, ImportBatch.days_since_last_file
    assert_not ImportBatch.stale?
  end

  test "a partir do prazo de tolerância a carteira fica desatualizada" do
    batch = import_synthetic_workbook
    batch.update_column(:created_at, ImportBatch::STALE_AFTER_DAYS.days.ago)

    assert_equal ImportBatch::STALE_AFTER_DAYS, ImportBatch.days_since_last_file
    assert_predicate ImportBatch, :stale?
  end

  # Lote pendente é importação em curso até o prazo; depois dele é worker parado, e a
  # diferença é o que a tela usa para avisar em vez de deixar o usuário esperando.
  test "lote pendente vira travado depois do prazo" do
    batch = ImportBatch.create!(file_checksum: "pendente", source_filename: "a.xlsx", status: "pending")

    assert_predicate batch, :running?
    assert_not batch.stuck?

    batch.update_column(:created_at, (ImportBatch::STUCK_AFTER + 1.minute).ago)

    assert_predicate batch, :stuck?
    assert_not batch.running?
  end

  test "lote validado nunca está em execução nem travado" do
    batch = import_synthetic_workbook

    assert_not batch.running?
    assert_not batch.stuck?
  end

  test "só lote falho e sem linhas gravadas pode ser descartado" do
    failed = ImportBatch.create!(file_checksum: "falho", source_filename: "a.xlsx", status: "failed")

    assert_predicate failed, :discardable?
    assert_not import_synthetic_workbook.discardable?
  end

  test "lote falho que já gravou linhas não pode ser descartado" do
    batch = import_synthetic_workbook
    batch.update!(status: "failed")

    assert_not batch.discardable?
  end

  test "worker vivo é o que bateu ponto dentro do tempo limite" do
    assert_not ImportBatch.worker_alive?, "sem processo registrado o worker está morto"

    process = SolidQueue::Process.create!(
      kind: "Worker", name: "worker-teste", pid: 999, hostname: "teste",
      last_heartbeat_at: Time.current
    )

    assert_predicate ImportBatch, :worker_alive?

    process.update!(last_heartbeat_at: (ImportBatch::WORKER_HEARTBEAT_TIMEOUT + 1.minute).ago)

    assert_not ImportBatch.worker_alive?
  end

  test "o batimento do dispatcher não conta como worker vivo" do
    SolidQueue::Process.create!(
      kind: "Dispatcher", name: "dispatcher-teste", pid: 998, hostname: "teste",
      last_heartbeat_at: Time.current
    )

    assert_not ImportBatch.worker_alive?
  end
end
