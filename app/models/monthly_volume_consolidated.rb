class MonthlyVolumeConsolidated < ApplicationRecord
  self.table_name = "monthly_volumes_consolidated"
  self.primary_key = nil

  belongs_to :channel
  belongs_to :establishment
  belongs_to :source_import_batch, class_name: "ImportBatch"
end
