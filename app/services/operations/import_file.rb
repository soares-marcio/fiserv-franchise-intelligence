require "digest"

module Operations
  class ImportFile
    # A planilha real tem ~430 KB para 553 ECs; o limite deixa folga de ~45x e ainda barra
    # um envio errado antes de o parse carregar o arquivo inteiro em memória.
    MAX_UPLOAD_BYTES = 20.megabytes

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
      if batch.status == "validated"
        raise ArgumentError, "Este arquivo já foi importado em " \
          "#{batch.created_at.strftime('%d/%m/%Y %H:%M')} " \
          "e o conteúdo é idêntico. Se a planilha foi atualizada, exporte de novo da origem."
      end
      if batch.status == "pending"
        raise ArgumentError, "Este arquivo já está na fila de importação. Acompanhe o lote " \
          "nesta tela; ele muda de status sozinho quando o worker terminar."
      end
      unless batch.discardable?
        raise ArgumentError, "Já existe um lote deste arquivo com dados gravados. Reprocesse " \
          "ou descarte o lote existente antes de enviar de novo."
      end

      batch.update!(source_filename: filename, status: "pending", validation_errors: [])
      batch
    end

    private_class_method :claim_batch, :handle_existing
  end
end
