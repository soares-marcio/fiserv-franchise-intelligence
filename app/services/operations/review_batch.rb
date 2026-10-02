module Operations
  # Aprovar ou rejeitar um lote em revisão.
  #
  # Aprovar é o que consolida: até aqui o lote tinha snapshots gravados, mas nenhuma tela o
  # enxergava. Rejeitar guarda o motivo e encerra — o arquivo fica no histórico, porque
  # saber o que foi recusado, e por quê, é parte da auditoria.
  class ReviewBatch
    def self.approve(batch:, reviewer:, note: nil)
      raise ArgumentError, "Este lote não está em revisão." unless batch.pending_review?

      review = BatchReview.new(batch)
      summary = { saindo: review.leaving.size, entrando: review.entering.size,
        mudando_de_mic: review.moving.size, reasons: batch.review_reasons }

      ApplicationRecord.transaction do
        BinImport::Importer.consolidate_batch!(batch)
        batch.update!(status: "validated", reviewed_by: reviewer, reviewed_at: Time.current,
          review_note: note)
      end
      # O resumo é do que foi decidido, em contagens: quem aprovou precisa poder responder
      # depois pelo que saiu da carteira naquele dia.
      Audit.record("batch.approved", user: reviewer, record: batch, metadata: summary)
      # Fora da transação: REFRESH CONCURRENTLY não roda dentro de uma.
      AuditViews.refresh!
      batch
    end

    def self.reject(batch:, reviewer:, note:)
      raise ArgumentError, "Este lote não está em revisão." unless batch.pending_review?
      raise ArgumentError, "Diga o motivo da recusa." if note.to_s.strip.empty?

      batch.update!(status: "rejected", reviewed_by: reviewer, reviewed_at: Time.current,
        review_note: note.to_s.strip)
      Audit.record("batch.rejected", user: reviewer, record: batch,
        metadata: { motivo: note.to_s.strip, motivos_da_revisao: batch.review_reasons })
      batch
    end
  end
end
