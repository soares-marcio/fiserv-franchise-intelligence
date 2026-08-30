class MapSnapshot < ApplicationRecord
  belongs_to :import_batch
  belongs_to :channel
  belongs_to :establishment
  belongs_to :sub_channel
  has_many :map_snapshot_actions, dependent: :destroy
end
