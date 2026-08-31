class CreateRemainingAuditViews < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE MATERIALIZED VIEW audit_stalled_companies AS
      SELECT arc.channel_id, arc.sub_channel_id, arc.establishment_id, arc.company_id, arc.cnpj, arc.max_known_day,
        arc.previous_revenue, arc.current_revenue
      FROM audit_revenue_by_company arc
      WHERE arc.previous_revenue > 0 AND arc.current_revenue = 0;
      CREATE UNIQUE INDEX index_audit_stalled_companies ON audit_stalled_companies (channel_id, establishment_id);

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

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS audit_company_ec_divergence, audit_pending_actions, audit_stalled_companies CASCADE"
  end
end
