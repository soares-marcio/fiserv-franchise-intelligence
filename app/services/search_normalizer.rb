# As buscas aceitam identificadores como o usuário cola: CNPJ com pontuação, EC com
# espaços. A versão só-dígitos do termo entra na consulta como alternativa; abaixo do
# mínimo ela viraria ruído (qualquer "1" casaria com quase tudo), então é descartada.
module SearchNormalizer
  MIN_DIGITS = 3

  def self.digits(query, min_length: MIN_DIGITS)
    digits = query.to_s.gsub(/\D/, "")
    digits if digits.length >= min_length
  end
end
