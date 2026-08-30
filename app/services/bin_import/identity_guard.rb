module BinImport
  class IdentityGuard
    def self.assert_existing!(channel, rows)
      rows.values.flatten.each do |row|
        establishment = Establishment.find_by(ec: Normalizer.ec(row["EC"]))
        next unless establishment

        cnpj = Normalizer.cnpj(row["CNPJ"])
        raise ArgumentError, "EC #{establishment.ec} mudou de CNPJ" if establishment.company.cnpj != cnpj
        raise ArgumentError, "EC #{establishment.ec} mudou de canal" if establishment.channel_id != channel.id
      end
    end
  end
end
