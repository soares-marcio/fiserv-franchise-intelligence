class RecreateAlignedAuditViewsWithSubChannelCutoff < ActiveRecord::Migration[8.1]
  # A view de faturamento por MIC passa a comparar cada MIC até o corte do arquivo dele
  # (AuditViews.sub_channel_cover_sql), e não até o do Master: com o Master em mais de um
  # arquivo, o MIC do arquivo que parou antes aparecia em queda pelos dias que não vieram.
  def up
    AuditViews.recreate!
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
