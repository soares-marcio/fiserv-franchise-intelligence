class RecreateAlignedAuditViewsBySubChannel < ActiveRecord::Migration[8.1]
  # A carteira vigente passa a ser escolhida por MIC (AuditViews.current_snapshots_sql): a
  # Fiserv manda a carteira de um Master em mais de um arquivo, e o lote mais novo do Master
  # apagava das views os MICs que vieram no outro arquivo.
  def up
    AuditViews.recreate!
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
