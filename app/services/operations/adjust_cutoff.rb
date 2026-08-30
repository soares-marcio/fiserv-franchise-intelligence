module Operations
  class AdjustCutoff
    NAME = "ajustar_dia_corte_mes_atual"

    def self.call(batch:, max_known_day:)
      cutoff = Integer(max_known_day)
      raise ArgumentError, "Dia de corte deve estar entre 1 e 31" unless cutoff.between?(1, 31)
      raise ArgumentError, "Lote sem competência atual" if batch.current_period.blank?

      coverage = PeriodCoverage.find_by!(channel_id: batch.channel_id, period: batch.current_period)
      coverage.update!(max_known_day: cutoff, last_import_batch: batch)
      batch.update!(current_month_cutoff_day: cutoff)
      AuditViews.refresh!
      coverage
    end
  end
end
