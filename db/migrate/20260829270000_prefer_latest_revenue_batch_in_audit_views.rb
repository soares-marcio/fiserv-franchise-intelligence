class PreferLatestRevenueBatchInAuditViews < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP MATERIALIZED VIEW IF EXISTS audit_stalled_companies CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_company CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_sub_channel CASCADE;

      CREATE MATERIALIZED VIEW audit_revenue_by_sub_channel AS
      WITH current_coverage AS (
        SELECT channel_id, period, max_known_day
        FROM period_coverages
        WHERE NOT closed
      ), aligned AS (
        SELECT c.channel_id, c.period AS current_period,
          c.max_known_day, (c.period - INTERVAL '1 month')::date AS previous_period
        FROM current_coverage c
      )
      SELECT rs.channel_id, rs.sub_channel_id, sc.name AS sub_channel_name, a.previous_period, a.current_period,
        a.max_known_day,
        COALESCE(SUM(CASE WHEN dr.period = a.previous_period THEN dr.amount END), 0) AS previous_revenue,
        COALESCE(SUM(CASE WHEN dr.period = a.current_period THEN dr.amount END), 0) AS current_revenue,
        COUNT(DISTINCT rs.establishment_id) FILTER (WHERE e.primary_establishment_id IS NULL) AS primary_establishments
      FROM revenue_snapshots rs
      JOIN sub_channels sc ON sc.id = rs.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id
      JOIN aligned a ON a.channel_id = rs.channel_id
      LEFT JOIN daily_revenues_consolidated dr ON dr.establishment_id = rs.establishment_id
        AND dr.channel_id = rs.channel_id AND dr.period IN (a.previous_period, a.current_period)
        AND dr.day <= a.max_known_day
      WHERE rs.import_batch_id = (
        SELECT MAX(ib.id) FROM import_batches ib
        WHERE ib.channel_id = rs.channel_id
          AND ib.status = 'validated'
          AND EXISTS (SELECT 1 FROM revenue_snapshots rsv WHERE rsv.import_batch_id = ib.id)
      )
      GROUP BY rs.channel_id, rs.sub_channel_id, sc.name, a.previous_period, a.current_period, a.max_known_day;
      CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel ON audit_revenue_by_sub_channel (channel_id, sub_channel_id);

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      SELECT ars.channel_id, ars.sub_channel_id, e.company_id, c.cnpj, ars.max_known_day,
        ars.previous_period, ars.current_period,
        COALESCE(SUM(CASE WHEN dr.period = ars.previous_period THEN dr.amount END), 0)
          AS previous_revenue,
        COALESCE(SUM(CASE WHEN dr.period = ars.current_period THEN dr.amount END), 0)
          AS current_revenue
      FROM audit_revenue_by_sub_channel ars
      JOIN revenue_snapshots rs
        ON rs.channel_id = ars.channel_id AND rs.sub_channel_id = ars.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id
      JOIN companies c ON c.id = e.company_id
      LEFT JOIN daily_revenues_consolidated dr
        ON dr.establishment_id = rs.establishment_id
        AND dr.channel_id = ars.channel_id
        AND dr.period IN (ars.previous_period, ars.current_period)
        AND dr.day <= ars.max_known_day
      WHERE rs.import_batch_id = (
        SELECT MAX(ib.id) FROM import_batches ib
        WHERE ib.channel_id = ars.channel_id
          AND ib.status = 'validated'
          AND EXISTS (SELECT 1 FROM revenue_snapshots rsv WHERE rsv.import_batch_id = ib.id)
      )
      GROUP BY ars.channel_id, ars.sub_channel_id, e.company_id, c.cnpj,
        ars.max_known_day, ars.previous_period, ars.current_period;
      CREATE UNIQUE INDEX index_audit_revenue_by_company
        ON audit_revenue_by_company (channel_id, sub_channel_id, company_id);

      CREATE MATERIALIZED VIEW audit_stalled_companies AS
      SELECT arc.channel_id, arc.sub_channel_id, sc.name AS sub_channel_name, arc.company_id, arc.cnpj,
        arc.max_known_day, arc.previous_revenue, arc.current_revenue
      FROM audit_revenue_by_company arc
      JOIN sub_channels sc ON sc.id = arc.sub_channel_id
      WHERE arc.previous_revenue > 0 AND arc.current_revenue = 0;
      CREATE UNIQUE INDEX index_audit_stalled_companies
        ON audit_stalled_companies (channel_id, sub_channel_id, company_id);
    SQL
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    execute <<~SQL
      DROP MATERIALIZED VIEW IF EXISTS audit_stalled_companies CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_company CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_sub_channel CASCADE;
    SQL
  end
end
