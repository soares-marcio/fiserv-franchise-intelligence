class SubChannel < ApplicationRecord
  include PublicIdentifier

  belongs_to :channel
  validates :name, presence: true, uniqueness: { scope: :channel_id }
end
