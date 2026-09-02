class ImportBinFileJob < ApplicationJob
  queue_as :default

  def perform(batch_id)
    batch = ImportBatch.find(batch_id)
    batch.source_file.blob.open do |file|
      BinImport::Importer.new(file.path, source_filename: batch.source_file.filename.to_s).call
    end
  rescue StandardError => error
    # Sem isto, uma falha antes do parse não deixaria rastro na tela de importação.
    batch&.reload&.update(status: "failed", validation_errors: [ error.message ])
    raise
  end
end
