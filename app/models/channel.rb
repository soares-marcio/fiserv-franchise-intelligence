class Channel < ApplicationRecord
  include PublicIdentifier

  # Todo Master pertence a uma organização, desde que nasce no import.
  belongs_to :organization
  has_many :sub_channels, dependent: :restrict_with_exception
  has_many :import_batches, dependent: :restrict_with_exception
  has_many :establishments, dependent: :restrict_with_exception
  belongs_to :deleted_by, class_name: "User", optional: true
  validates :external_id, :name, presence: true

  # Apagado é marcado, não removido: os dados ficam e só a plataforma restaura. Sem
  # default_scope, de propósito — quem lista Master diz se quer os ativos ou os apagados.
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def deleted? = deleted_at.present?
end
