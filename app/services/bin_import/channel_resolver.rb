module BinImport
  class ChannelResolver
    # Nome de um canal criado sem CANAL na planilha. A carteira entra e fica visível, em vez
    # de o arquivo inteiro ser recusado por uma coluna vazia; o analista vê pelo nome que
    # falta definir o canal, e as linhas sem CANAL viram anomalia no mesmo import.
    FALLBACK_NAME = "SEM CANAL".freeze

    # O REPORT_ID é a identidade do canal. Sem CANAL na planilha, um REPORT_ID já conhecido
    # mantém o nome que tem — uma planilha incompleta não pode renomear a carteira.
    def self.call(report_id:, name:)
      channel = Channel.find_by(external_id: report_id)
      return channel if channel && name.blank?

      resolved = name.presence || FALLBACK_NAME
      if channel && channel.name != resolved
        raise ArgumentError, "REPORT_ID #{report_id} associado a outro CANAL"
      end

      channel || Channel.create!(external_id: report_id, name: resolved)
    end
  end
end
