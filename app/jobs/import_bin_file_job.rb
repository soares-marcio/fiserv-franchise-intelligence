class ImportBinFileJob < ApplicationJob
  queue_as :default

  def perform(blob_signed_id)
    blob = ActiveStorage::Blob.find_signed!(blob_signed_id)
    blob.open do |file|
      batch = BinImport::Importer.new(file.path, source_filename: blob.filename.to_s).call
      batch.source_file.attach(blob)
    end
  end
end
