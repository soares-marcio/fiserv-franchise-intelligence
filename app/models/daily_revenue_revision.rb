class DailyRevenueRevision < ApplicationRecord
  belongs_to :establishment
  belongs_to :import_batch
end
