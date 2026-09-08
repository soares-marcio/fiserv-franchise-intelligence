module BinImport
  class IdentityGuard
    def self.assert_existing!(channel, rows)
      entries = rows.values.flatten
      # Duas consultas para a planilha inteira: era um SELECT de estabelecimento e outro de
      # empresa por linha de cada aba, e as três abas repetem os mesmos ECs.
      known = Establishment.where(ec: entries.map { |row| Normalizer.ec(row["EC"]) }.uniq)
        .includes(:company).index_by(&:ec)

      entries.each do |row|
        establishment = known[Normalizer.ec(row["EC"])]
        next unless establishment

        cnpj = Normalizer.cnpj(row["CNPJ"])
        if establishment.company.cnpj != cnpj
        raise ArgumentError, "O EC #{establishment.ec} já está cadastrado com outro CNPJ. " \
          "O EC é preso ao CNPJ desde a primeira importação: confira as duas colunas na " \
          "planilha, ou avise a Fiserv se a troca for real."
        end
        if establishment.channel_id != channel.id
        raise ArgumentError, "O EC #{establishment.ec} já pertence a outro canal. " \
          "Um EC não muda de carteira entre importações: confira o CANAL da planilha."
        end
      end
    end
  end
end
