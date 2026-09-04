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
        raise ArgumentError, "EC #{establishment.ec} mudou de CNPJ" if establishment.company.cnpj != cnpj
        raise ArgumentError, "EC #{establishment.ec} mudou de canal" if establishment.channel_id != channel.id
      end
    end
  end
end
