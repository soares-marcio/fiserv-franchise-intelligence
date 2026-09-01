require "test_helper"

class Operations::ImportFileTest < ActiveJob::TestCase
  setup do
    @path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-upload.xlsx")
    BinWorkbook.write(@path)
  end

  teardown do
    File.delete(@path) if File.exist?(@path)
  end

  test "anexa o upload ao lote antes de enfileirar" do
    batch = nil

    assert_enqueued_with(job: ImportBinFileJob) do
      batch = Operations::ImportFile.call(upload)
    end

    assert_predicate batch.source_file, :attached?
    assert_equal @path.basename.to_s, batch.source_file.filename.to_s
    assert batch.source_file.blob.service.exist?(batch.source_file.blob.key)
  end

  test "não cria outro lote nem outro blob enquanto o mesmo arquivo está pendente" do
    Operations::ImportFile.call(upload)

    assert_no_difference [ -> { ImportBatch.count }, -> { ActiveStorage::Blob.count } ] do
      error = assert_raises(ArgumentError) { Operations::ImportFile.call(upload) }
      assert_equal "Arquivo já está sendo importado", error.message
    end
    assert_enqueued_jobs 1, only: ImportBinFileJob
  end

  test "mantém arquivo ligado ao lote e marca falha se a fila recusar o job" do
    original_enqueue = ImportBinFileJob.method(:perform_later)
    ImportBinFileJob.define_singleton_method(:perform_later) { |*| raise "fila indisponível" }
    error = assert_raises(RuntimeError) { Operations::ImportFile.call(upload) }

    batch = ImportBatch.last
    assert_equal "fila indisponível", error.message
    assert_equal "failed", batch.status
    assert_equal [ "fila indisponível" ], batch.validation_errors
    assert_predicate batch.source_file, :attached?
  ensure
    ImportBinFileJob.define_singleton_method(:perform_later, original_enqueue) if original_enqueue
  end

  private

  def upload
    Rack::Test::UploadedFile.new(
      @path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
  end
end
