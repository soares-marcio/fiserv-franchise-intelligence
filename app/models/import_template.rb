class ImportTemplate < ApplicationRecord
  has_many :import_template_columns, dependent: :destroy
  has_many :import_batches, dependent: :restrict_with_exception
end
