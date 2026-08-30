require "test_helper"

class Operations::ImportFileTest < ActiveJob::TestCase
  test "stores the upload in Active Storage and enqueues its signed identifier" do
    path = Rails.root.join("1478_MASTER_FRANQUEADO_RAMOS_E_SILVA_20260825.xlsx")
    upload = Rack::Test::UploadedFile.new(
      path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    assert_enqueued_with(job: ImportBinFileJob) do
      Operations::ImportFile.call(upload)
    end

    blob = ActiveStorage::Blob.last
    assert_equal path.basename.to_s, blob.filename.to_s
    assert blob.service.exist?(blob.key)
  end
end
