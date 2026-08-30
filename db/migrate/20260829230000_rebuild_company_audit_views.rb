class RebuildCompanyAuditViews < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP MATERIALIZED VIEW IF EXISTS audit_stalled_companies CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_company CASCADE;

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      SELECT ars.channel_id, ars.sub_channel_id, e.company_id, c.cnpj, ars.max_dia_conhecido,
        ars.competencia_m1, ars.competencia_atual,
        COALESCE(SUM(CASE WHEN dr.competencia = ars.competencia_m1 THEN dr.amount END), 0)
          AS faturamento_m1,
        COALESCE(SUM(CASE WHEN dr.competencia = ars.competencia_atual THEN dr.amount END), 0)
          AS faturamento_atual
      FROM audit_revenue_by_sub_channel ars
      JOIN revenue_snapshots rs
        ON rs.channel_id = ars.channel_id AND rs.sub_channel_id = ars.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id
      JOIN companies c ON c.id = e.company_id
      LEFT JOIN daily_revenues_consolidated dr
        ON dr.establishment_id = rs.establishment_id
        AND dr.channel_id = ars.channel_id
        AND dr.competencia IN (ars.competencia_m1, ars.competencia_atual)
        AND dr.day <= ars.max_dia_conhecido
      WHERE rs.import_batch_id = (
        SELECT MAX(ib.id) FROM import_batches ib
        WHERE ib.channel_id = ars.channel_id AND ib.status = 'validated'
      )
      GROUP BY ars.channel_id, ars.sub_channel_id, e.company_id, c.cnpj,
        ars.max_dia_conhecido, ars.competencia_m1, ars.competencia_atual;
      CREATE UNIQUE INDEX index_audit_revenue_by_company
        ON audit_revenue_by_company (channel_id, sub_channel_id, company_id);

      CREATE MATERIALIZED VIEW audit_stalled_companies AS
      SELECT arc.channel_id, arc.sub_channel_id, sc.sub_canal, arc.company_id, arc.cnpj,
        arc.max_dia_conhecido, arc.faturamento_m1, arc.faturamento_atual
      FROM audit_revenue_by_company arc
      JOIN sub_channels sc ON sc.id = arc.sub_channel_id
      WHERE arc.faturamento_m1 > 0 AND arc.faturamento_atual = 0;
      CREATE UNIQUE INDEX index_audit_stalled_companies
        ON audit_stalled_companies (channel_id, sub_channel_id, company_id);
    SQL
  end

  def down
    execute <<~SQL
      DROP MATERIALIZED VIEW IF EXISTS audit_stalled_companies CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_company CASCADE;
    SQL
  end
end
