class Company < ApplicationRecord
  include PublicIdentifier

  has_many :establishments, dependent: :restrict_with_exception
  validates :cnpj, format: { with: /\A\d{14}\z/ }, uniqueness: true
end
