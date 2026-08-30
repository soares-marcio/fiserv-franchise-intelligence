class Channel < ApplicationRecord
  include PublicIdentifier

  has_many :sub_channels, dependent: :restrict_with_exception
  has_many :import_batches, dependent: :restrict_with_exception
  has_many :establishments, dependent: :restrict_with_exception
  validates :external_id, :canal, presence: true
end
