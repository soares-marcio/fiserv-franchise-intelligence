class ActivationProposal < ApplicationRecord
  belongs_to :import_batch
  belongs_to :channel
  belongs_to :sub_channel
  belongs_to :company
  belongs_to :establishment, optional: true
end
