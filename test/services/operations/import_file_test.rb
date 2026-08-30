require "test_helper"

class Operations::ImportFileTest < ActiveJob::TestCase
  test "guarda o upload no Active Storage e enfileira o identificador assinado" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-upload.xlsx")
    BinWorkbook.write(path)
    upload = Rack::Test::UploadedFile.new(
      path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    assert_enqueued_with(job: ImportBinFileJob) do
      Operations::ImportFile.call(upload)
    end

    blob = ActiveStorage::Blob.last
    assert_equal path.basename.to_s, blob.filename.to_s
    assert blob.service.exist?(blob.key)
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
