class Channel < ApplicationRecord
  include PublicIdentifier

  # Todo Master pertence a uma organização, desde que nasce no import.
  belongs_to :organization
  has_many :sub_channels, dependent: :restrict_with_exception
  has_many :import_batches, dependent: :restrict_with_exception
  has_many :establishments, dependent: :restrict_with_exception
  validates :external_id, :name, presence: true
end
