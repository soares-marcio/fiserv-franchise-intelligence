module Operations
  # Aprovar ou rejeitar um lote em revisão.
  #
  # Aprovar é o que consolida: até aqui o lote tinha snapshots gravados, mas nenhuma tela o
  # enxergava. Rejeitar guarda o motivo e encerra — o arquivo fica no histórico, porque
  # saber o que foi recusado, e por quê, é parte da auditoria.
  class ReviewBatch
    def self.approve(batch:, reviewer:, note: nil)
      raise ArgumentError, "Este lote não está em revisão." unless batch.pending_review?

      ApplicationRecord.transaction do
        BinImport::Importer.consolidate_batch!(batch)
        batch.update!(status: "validated", reviewed_by: reviewer, reviewed_at: Time.current,
          review_note: note)
      end
      # Fora da transação: REFRESH CONCURRENTLY não roda dentro de uma.
      AuditViews.refresh!
      batch
    end

    def self.reject(batch:, reviewer:, note:)
      raise ArgumentError, "Este lote não está em revisão." unless batch.pending_review?
      raise ArgumentError, "Diga o motivo da recusa." if note.to_s.strip.empty?

      batch.update!(status: "rejected", reviewed_by: reviewer, reviewed_at: Time.current,
        review_note: note.to_s.strip)
      batch
    end
  end
end
