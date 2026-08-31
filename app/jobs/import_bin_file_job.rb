class ImportBinFileJob < ApplicationJob
  queue_as :default

  def perform(batch_id, blob_signed_id)
    batch = ImportBatch.find(batch_id)
    blob = ActiveStorage::Blob.find_signed!(blob_signed_id)
    # Anexa antes de importar: se falhar, o arquivo fica inspecionável no lote e some
    # junto com ele no reenvio, em vez de virar blob órfão no volume.
    batch.source_file.attach(blob)
    blob.open do |file|
      BinImport::Importer.new(file.path, source_filename: blob.filename.to_s).call
    end
  rescue StandardError => error
    # Sem isto, uma falha antes do parse não deixaria rastro na tela de importação.
    batch&.reload&.update(status: "failed", validation_errors: [ error.message ])
    raise
  end
end
