module BinImport
  class IdentityGuard
    def self.assert_existing!(channel, rows)
      entries = rows.values.flatten
      # Duas consultas para a planilha inteira: era um SELECT de estabelecimento e outro de
      # empresa por linha de cada aba, e as três abas repetem os mesmos ECs.
      known = Establishment.active.where(ec: entries.map { |row| Normalizer.ec(row["EC"]) }.uniq)
        .includes(:company, :channel).index_by(&:ec)

      entries.each do |row|
        establishment = known[Normalizer.ec(row["EC"])]
        next unless establishment

        # A organização vem antes do CNPJ e do canal: dizer "outro CNPJ" ou "outro canal" a
        # quem não deveria saber que o EC existe já contaria demais.
        if establishment.channel.organization_id != channel.organization_id
        raise ArgumentError, "O EC #{establishment.ec} já está cadastrado fora da sua organização e " \
          "não pode entrar por este arquivo. Confira a planilha enviada."
        end
        cnpj = Normalizer.cnpj(row["CNPJ"])
        if establishment.company.cnpj != cnpj
        raise ArgumentError, "O EC #{establishment.ec} já está cadastrado com outro CNPJ. " \
          "O EC é preso ao CNPJ desde a primeira importação: confira as duas colunas na " \
          "planilha, ou avise a Fiserv se a troca for real."
        end
        if establishment.channel_id != channel.id
        raise ArgumentError, other_channel_message(channel, establishment, known.values)
        end
      end
    end

    # O CANAL pode trazer o mesmo nome e o REPORT_ID não (lote #46, 03/11/2026: o arquivo de
    # Águas Lindas voltou com o 719 do Master juntado ao 1478). Quem envia precisa ver os
    # dois REPORT_IDs lado a lado; "outro canal" sozinho parecia erro do portal.
    def self.other_channel_message(channel, establishment, known)
      owner = establishment.channel
      others = known.count { |candidate| candidate.channel_id == owner.id } - 1
      along = { 0 => "", 1 => ", junto com outro EC deste arquivo" }
        .fetch(others, ", junto com outros #{others} ECs deste arquivo")
      unknown = "Nenhum Master ativo usa o REPORT_ID #{channel.external_id}. " if channel.new_record?

      "O arquivo traz o REPORT_ID #{channel.external_id}, mas o EC #{establishment.ec} já " \
        "pertence ao Master \"#{owner.name}\", de REPORT_ID #{owner.external_id}#{along}. " \
        "#{unknown}Um EC não muda de Master entre importações: confira a coluna REPORT_ID da planilha."
    end
    private_class_method :other_channel_message
  end
end
