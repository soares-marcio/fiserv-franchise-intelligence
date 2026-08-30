module Operations
  class ConfirmDuplicate
    NAME = "confirmar_duplicata_ec"

    def self.call(establishment:, primary:)
      raise ArgumentError, "EC principal é obrigatório" if primary.blank?
      raise ArgumentError, "Um EC não pode ser principal de si mesmo" if establishment.id == primary.id
      raise ArgumentError, "A duplicata deve pertencer ao mesmo CNPJ" if establishment.company_id != primary.company_id
      raise ArgumentError, "Os ECs devem ser do mesmo canal" if establishment.channel_id != primary.channel_id

      establishment.update!(
        primary_establishment: primary,
        duplicate_reason: "confirmado_manualmente",
        duplicate_confirmed_at: Time.current
      )
      AuditViews.refresh!
      establishment
    end
  end
end
