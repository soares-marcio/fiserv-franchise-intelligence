require "digest"

module Operations
  class ImportFile
    NAME = "importar_arquivo"

    # O lote nasce aqui, antes de o arquivo ser lido: se o job morrer no caminho,
    # a falha tem onde aparecer. O Importer reencontra este lote pelo checksum.
    def self.call(upload)
      checksum = Digest::SHA256.file(upload.tempfile.path).hexdigest
      if ImportBatch.validated.exists?(file_checksum: checksum)
        raise ArgumentError, "Arquivo já importado"
      end

      ImportBatch.where(file_checksum: checksum).where.not(status: "validated").destroy_all
      blob = ActiveStorage::Blob.create_and_upload!(
        io: upload, filename: upload.original_filename,
        content_type: upload.content_type, identify: false
      )
      batch = ImportBatch.create!(
        source_filename: upload.original_filename, file_checksum: checksum, status: "pending"
      )
      ImportBinFileJob.perform_later(batch.id, blob.signed_id)
      batch
    end
  end
end
