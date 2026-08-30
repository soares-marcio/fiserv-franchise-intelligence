class DataAnomaly < ApplicationRecord
  include PublicIdentifier

  belongs_to :channel
  belongs_to :company, optional: true
  belongs_to :establishment, optional: true
  belongs_to :first_import_batch, class_name: "ImportBatch"
  belongs_to :last_import_batch, class_name: "ImportBatch"
end
