class RevenueSnapshot < ApplicationRecord
  belongs_to :import_batch
  belongs_to :channel
  belongs_to :establishment
  belongs_to :sub_channel
end
