class ImportBatch < ApplicationRecord
  include PublicIdentifier

  has_one_attached :source_file

  belongs_to :channel
  belongs_to :import_template
  has_many :revenue_snapshots, dependent: :restrict_with_exception
  has_many :map_snapshots, dependent: :restrict_with_exception
  has_many :activation_proposals, dependent: :restrict_with_exception
  has_many :daily_revenues, dependent: :restrict_with_exception
  has_many :monthly_volumes, dependent: :restrict_with_exception

  validates :file_checksum, uniqueness: true
end
