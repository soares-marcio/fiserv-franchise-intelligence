class SubChannel < ApplicationRecord
  include PublicIdentifier

  belongs_to :channel
  validates :sub_canal, presence: true, uniqueness: { scope: :channel_id }
end
