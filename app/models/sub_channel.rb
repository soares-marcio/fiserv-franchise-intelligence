class SubChannel < ApplicationRecord
  include PublicIdentifier

  belongs_to :channel
  belongs_to :deleted_by, class_name: "User", optional: true
  # Único entre os ativos: o MIC apagado volta como MIC novo na planilha seguinte.
  validates :name, presence: true, uniqueness: { scope: :channel_id, conditions: -> { active } }

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def deleted? = deleted_at.present?
end
