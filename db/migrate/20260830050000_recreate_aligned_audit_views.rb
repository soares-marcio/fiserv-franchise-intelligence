class RecreateAlignedAuditViews < ActiveRecord::Migration[8.1]
  # As views de comparação alinhada passam a ser definidas por AuditViews, junto com o
  # SQL que o ReportScope usa. Ganham faturamento_m1_cheio e passam a listar os CNPJs
  # que não venderam nenhum dia no mês atual, antes eliminados pelo JOIN interno.
  def up
    AuditViews.recreate!
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
