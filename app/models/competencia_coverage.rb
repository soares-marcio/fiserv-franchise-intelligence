class CompetenciaCoverage < ApplicationRecord
  belongs_to :channel
  belongs_to :ultimo_import_batch, class_name: "ImportBatch"
end
