class PeriodCoverage < ApplicationRecord
  # A tabela é chaveada por (canal, competência) e não tem coluna id; sem declarar isso
  # o UPDATE sai com WHERE vazio. As associações precisam da chave estrangeira explícita
  # porque o Rails não consegue derivá-la de uma chave composta.
  query_constraints :channel_id, :period

  belongs_to :channel, foreign_key: :channel_id
  belongs_to :last_import_batch, class_name: "ImportBatch", foreign_key: :last_import_batch_id
end
