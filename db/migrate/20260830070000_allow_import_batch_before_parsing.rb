class AllowImportBatchBeforeParsing < ActiveRecord::Migration[8.1]
  # O lote passa a ser criado no upload, antes de o arquivo ser lido, para que uma
  # falha na leitura apareça na tela em vez de sumir. Canal e template só são
  # conhecidos depois do parse.
  def change
    change_column_null :import_batches, :channel_id, true
    change_column_null :import_batches, :import_template_id, true
  end
end
