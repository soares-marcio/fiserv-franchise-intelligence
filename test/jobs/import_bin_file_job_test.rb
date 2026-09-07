require "test_helper"

# O job é a única porta do import em produção: o que ele faz com uma falha decide se o
# usuário vê "falhou" na tela ou se o lote é retomado sozinho.
class ImportBinFileJobTest < ActiveJob::TestCase
  setup do
    @path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-BIN_TESTE_20260811.xlsx")
    BinWorkbook.write(@path)
    @batch = Operations::ImportFile.call(upload)
  end

  teardown do
    File.delete(@path) if File.exist?(@path)
  end

  test "importa a planilha anexada e deixa o lote validado" do
    ImportBinFileJob.perform_now(@batch.id)

    assert_equal "validated", @batch.reload.status
    assert_equal 3, @batch.map_snapshots.count
  end

  test "erro definitivo marca o lote como falho com a mensagem na tela" do
    with_importer_raising(ArgumentError.new("Cabeçalhos divergentes")) do
      assert_raises(ArgumentError) { ImportBinFileJob.perform_now(@batch.id) }
    end

    assert_equal "failed", @batch.reload.status
    assert_equal [ "Cabeçalhos divergentes" ], @batch.validation_errors
  end

  # Banco reiniciado no meio do import é falha transitória: marcar o lote como falho
  # esconderia que ele ainda vai ser retomado, e o usuário reenviaria o arquivo à toa.
  test "queda de conexão reenfileira o job e não marca o lote como falho" do
    with_importer_raising(PG::ConnectionBad.new("servidor encerrou a conexão")) do
      assert_enqueued_with(job: ImportBinFileJob) do
        ImportBinFileJob.perform_now(@batch.id)
      end
    end

    assert_equal "pending", @batch.reload.status
  end

  test "na última tentativa o lote é marcado como falho" do
    job = ImportBinFileJob.new(@batch.id)
    # Duas quedas já registradas: esta execução é a terceira e última.
    job.exception_executions = { ImportBinFileJob::RETRYABLE.to_s => ImportBinFileJob::ATTEMPTS - 1 }

    with_importer_raising(PG::ConnectionBad.new("servidor encerrou a conexão")) do
      assert_raises(PG::ConnectionBad) { job.perform_now }
    end

    assert_equal "failed", @batch.reload.status
  end

  # Dois imports simultâneos disputam a partição, a consolidação e o refresh das views.
  test "roda um import por vez" do
    assert_equal 1, ImportBinFileJob.concurrency_limit
    assert_equal "ImportBinFileJob/bin_import", ImportBinFileJob.new(@batch.id).concurrency_key
  end

  private

  def upload
    Rack::Test::UploadedFile.new(
      @path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
  end

  # Sem biblioteca de stub no projeto: o construtor do importador é trocado pelo tempo do bloco.
  def with_importer_raising(error)
    original = BinImport::Importer.method(:new)
    BinImport::Importer.define_singleton_method(:new) { |*, **| raise error }
    yield
  ensure
    BinImport::Importer.define_singleton_method(:new, original)
  end
end
