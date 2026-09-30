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
  def suspended? = suspended_at.present?

  # Suspender é reversível e não toca em conta nem em dado: só fecha a porta. As sessões
  # abertas caem na hora, como na desativação de uma conta.
  def suspend!
    transaction do
      update!(suspended_at: Time.current)
      Session.where(user_id: users.select(:id)).destroy_all
    end
  end

  def reactivate!
    update!(suspended_at: nil)
  end

  private

  def name_not_blank_when_present
    return if name.nil? || name.strip.present?

    errors.add(:name, "não pode ficar em branco")
  end
end
