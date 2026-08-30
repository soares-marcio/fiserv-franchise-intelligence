class DailyRevenueConsolidated < ApplicationRecord
  self.table_name = "daily_revenues_consolidated"
  self.primary_key = nil

  belongs_to :establishment
  belongs_to :channel
  belongs_to :source_import_batch, class_name: "ImportBatch"
end
