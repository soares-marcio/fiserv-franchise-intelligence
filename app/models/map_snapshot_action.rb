class MapSnapshotAction < ApplicationRecord
  belongs_to :map_snapshot
  belongs_to :conversation_action
end
