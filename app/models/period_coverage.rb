class PeriodCoverage < ApplicationRecord
  # A tabela é chaveada por (canal, competência) e não tem coluna id; sem declarar isso
  # o UPDATE sai com WHERE vazio. As associações precisam da chave estrangeira explícita
  # porque o Rails não consegue derivá-la de uma chave composta.
  query_constraints :channel_id, :period

  belongs_to :channel, foreign_key: :channel_id
  belongs_to :last_import_batch, class_name: "ImportBatch", foreign_key: :last_import_batch_id

  # Toda consolidação (lote validado ou reprocessado) e todo ajuste de corte tocam esta
  # tabela; o último updated_at, portanto, muda sempre que os agregados podem ter mudado.
  # Serve de chave de cache para os relatórios que leem as tabelas consolidadas.
  def self.consolidation_stamp
    maximum(:updated_at)&.iso8601(6)
  end
end
