class DropUnusedAuditViewsAndColumns < ActiveRecord::Migration[8.1]
  def up
    # Nenhum código lê estas duas views, nenhuma outra view depende delas e o banco não
    # registrou um único scan desde 04/09. O consumidor previsto era o Metabase, que nunca
    # passou pelo setup. Saem também do REFRESH que roda a cada import.
    execute "DROP MATERIALIZED VIEW audit_pending_actions"
    execute "DROP MATERIALIZED VIEW audit_company_ec_divergence"

    # Colunas que nenhum código escreve ou lê e que estão vazias no banco.
    remove_column :establishments, :duplicate_confirmed_by
    remove_column :import_template_columns, :target_table
    remove_column :import_template_columns, :target_field
  end

  def down
    add_column :import_template_columns, :target_field, :string
    add_column :import_template_columns, :target_table, :string
    add_column :establishments, :duplicate_confirmed_by, :string

    execute <<~SQL
      CREATE MATERIALIZED VIEW audit_pending_actions AS
      SELECT ms.channel_id, ms.sub_channel_id, e.company_id, ca.text, COUNT(*) AS total
      FROM map_snapshot_actions msa
      JOIN map_snapshots ms ON ms.id = msa.map_snapshot_id
      JOIN establishments e ON e.id = ms.establishment_id
      JOIN conversation_actions ca ON ca.id = msa.conversation_action_id
      GROUP BY ms.channel_id, ms.sub_channel_id, e.company_id, ca.text;
      CREATE UNIQUE INDEX index_audit_pending_actions ON audit_pending_actions (channel_id, sub_channel_id, company_id, text);

      CREATE MATERIALIZED VIEW audit_company_ec_divergence AS
      SELECT rs.channel_id, e.company_id,
        COUNT(DISTINCT rs.contract_status) AS distinct_contract_statuses,
        COUNT(DISTINCT ms.performed_segment) AS distinct_performed_segments
      FROM revenue_snapshots rs
      JOIN establishments e ON e.id = rs.establishment_id
      LEFT JOIN map_snapshots ms ON ms.import_batch_id = rs.import_batch_id AND ms.establishment_id = rs.establishment_id
      GROUP BY rs.channel_id, e.company_id
      HAVING COUNT(DISTINCT rs.contract_status) > 1 OR COUNT(DISTINCT ms.performed_segment) > 1;
      CREATE UNIQUE INDEX index_audit_company_ec_divergence ON audit_company_ec_divergence (channel_id, company_id);
    SQL
  end
end
