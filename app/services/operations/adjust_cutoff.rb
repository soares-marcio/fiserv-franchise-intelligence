module Operations
  class AdjustCutoff
    NAME = "ajustar_dia_corte_mes_atual"

    def self.call(batch:, max_dia_conhecido:)
      cutoff = Integer(max_dia_conhecido)
      raise ArgumentError, "Dia de corte deve estar entre 1 e 31" unless cutoff.between?(1, 31)
      raise ArgumentError, "Lote sem competência atual" if batch.competencia_atual.blank?

      coverage = CompetenciaCoverage.find_by!(channel_id: batch.channel_id, competencia: batch.competencia_atual)
      coverage.update!(max_dia_conhecido: cutoff, ultimo_import_batch: batch)
      batch.update!(dia_corte_mes_atual: cutoff)
      AuditViews.refresh!
      coverage
    end
  end
end
