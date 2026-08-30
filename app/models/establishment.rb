class Establishment < ApplicationRecord
  include PublicIdentifier

  belongs_to :company
  belongs_to :channel
  belongs_to :primary_establishment, class_name: "Establishment", optional: true
  has_many :duplicate_establishments, class_name: "Establishment", foreign_key: :primary_establishment_id,
    dependent: :restrict_with_exception
  has_many :map_snapshots, dependent: :restrict_with_exception
  has_one :current_map_snapshot, -> { order(id: :desc) }, class_name: "MapSnapshot"
  has_many :revenue_snapshots, dependent: :restrict_with_exception

  validates :ec, format: { with: /\A\d{8}\z/ }, uniqueness: true
  validate :primary_is_from_same_company

  private

  def primary_is_from_same_company
    return if primary_establishment.blank? || primary_establishment.company_id == company_id

    errors.add(:primary_establishment, "deve pertencer ao mesmo CNPJ")
  end
end
