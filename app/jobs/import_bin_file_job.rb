class ImportBinFileJob < ApplicationJob
  queue_as :default

  def perform(batch_id, blob_signed_id)
    batch = ImportBatch.find(batch_id)
    blob = ActiveStorage::Blob.find_signed!(blob_signed_id)
    blob.open do |file|
      BinImport::Importer.new(file.path, source_filename: blob.filename.to_s).call
    end
    batch.reload.source_file.attach(blob)
  rescue StandardError => error
    # Sem isto, uma falha antes do parse não deixaria rastro na tela de importação.
    batch&.reload&.update(status: "failed", validation_errors: [ error.message ])
    raise
  end
end
