class ConversationAction < ApplicationRecord
  has_many :map_snapshot_actions, dependent: :restrict_with_exception
end
