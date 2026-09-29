# A unidade de isolamento do portal: Masters, contas, lotes e anotações pertencem a uma
# organização, e nenhuma enxerga a outra — nem a plataforma. Nasce sem nome; quem a
# administra dá o nome no primeiro acesso.
class Organization < ApplicationRecord
  include PublicIdentifier

  has_many :users, dependent: :restrict_with_exception
  has_many :channels, dependent: :restrict_with_exception
  has_many :import_batches, dependent: :restrict_with_exception

  # Nulo é "ainda sem nome"; em branco não é nome nenhum. O banco tem o mesmo CHECK.
  validates :name, uniqueness: true, allow_nil: true
  validate :name_not_blank_when_present

  def named? = name.present?

  private

  def name_not_blank_when_present
    return if name.nil? || name.strip.present?

    errors.add(:name, "não pode ficar em branco")
  end
end
