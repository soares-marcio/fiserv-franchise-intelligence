class MonthlyVolume < ApplicationRecord
  belongs_to :import_batch
  belongs_to :channel
  belongs_to :establishment
end
