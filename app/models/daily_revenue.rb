class DailyRevenue < ApplicationRecord
  self.primary_key = "id"

  belongs_to :import_batch
  belongs_to :channel
  belongs_to :establishment
end
