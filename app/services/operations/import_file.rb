require "digest"

module Operations
  class ImportFile
    NAME = "importar_arquivo"

    # O lote nasce aqui, antes de o arquivo ser lido: se o job morrer no caminho,
    # a falha tem onde aparecer. A unicidade do checksum fecha uploads concorrentes.
    def self.call(upload)
      checksum = Digest::SHA256.file(upload.tempfile.path).hexdigest
      batch = claim_batch(checksum, upload.original_filename)
      batch.source_file.purge if batch.source_file.attached?
      batch.source_file.attach(
        io: upload, filename: upload.original_filename,
        content_type: upload.content_type, identify: false
      )
      job = ImportBinFileJob.perform_later(batch.id)
      raise job.enqueue_error if job.enqueue_error

      batch
    rescue ArgumentError
      raise
    rescue StandardError => error
      batch&.update(status: "failed", validation_errors: [ error.message ])
      raise
    end

    def self.claim_batch(checksum, filename)
      batch = ImportBatch.find_by(file_checksum: checksum)
      return handle_existing(batch, filename) if batch

      ImportBatch.create!(source_filename: filename, file_checksum: checksum, status: "pending")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      batch = ImportBatch.find_by(file_checksum: checksum)
      raise error unless batch

      handle_existing(batch, filename)
    end

    def self.handle_existing(batch, filename)
      raise ArgumentError, "Arquivo já importado" if batch.status == "validated"
      raise ArgumentError, "Arquivo já está sendo importado" if batch.status == "pending"
      raise ArgumentError, "Lote existente precisa ser reprocessado" unless batch.discardable?

      batch.update!(source_filename: filename, status: "pending", validation_errors: [])
      batch
    end

    private_class_method :claim_batch, :handle_existing
  end
end
