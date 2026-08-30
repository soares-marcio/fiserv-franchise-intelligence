module Operations
  class ReprocessBatch
    NAME = "reprocessar_batch"

    def self.call(batch)
      raise ArgumentError, "Só é possível reprocessar lote validado" unless batch.status == "validated"

      BinImport::Consolidator.new(batch).call
      AuditViews.refresh!
      batch
    end
  end
end
