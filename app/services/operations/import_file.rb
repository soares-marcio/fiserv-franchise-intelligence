module Operations
  class ImportFile
    NAME = "importar_arquivo"

    def self.call(upload)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: upload, filename: upload.original_filename,
        content_type: upload.content_type, identify: false
      )
      ImportBinFileJob.perform_later(blob.signed_id)
    end
  end
end
