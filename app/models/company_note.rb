# Anotação do analista sobre um cliente. Presa ao CNPJ, e não a uma FK para companies: id e
# uuid são regenerados a cada recriação do banco, e o CNPJ não — ele vem da planilha. Ver o
# comentário da migration para o porquê inteiro.
class CompanyNote < ApplicationRecord
  has_rich_text :body

  validates :cnpj, format: { with: /\A\d{14}\z/ }, uniqueness: true

  # A empresa correspondente, quando ela existe na carteira importada. Pode não existir — é
  # o preço, aceito, de não ter FK: a anotação sobrevive ao cliente sair de uma planilha.
  def company
    Company.find_by(cnpj:)
  end
end
