# Anotação do analista sobre um cliente. Presa ao CNPJ, e não a uma FK para companies: id e
# uuid são regenerados a cada recriação do banco, e o CNPJ não — ele vem da planilha. Ver o
# comentário da migration para o porquê inteiro.
class CompanyNote < ApplicationRecord
  has_rich_text :body
  # Nulável de propósito: as anotações anteriores ao login não têm autor.
  belongs_to :author, class_name: "User", optional: true
  # Uma anotação por cliente **por organização**: o mesmo CNPJ em duas organizações são
  # duas anotações que não se veem.
  belongs_to :organization

  validates :cnpj, format: { with: /\A\d{14}\z/ }, uniqueness: { scope: :organization_id }

  # A empresa correspondente, quando ela existe na carteira importada. Pode não existir — é
  # o preço, aceito, de não ter FK: a anotação sobrevive ao cliente sair de uma planilha.
  def company
    Company.find_by(cnpj:)
  end
end
