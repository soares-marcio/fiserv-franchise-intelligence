class CreateAuditViews < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
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
      WHERE rs.import_batch_id = (SELECT MAX(ib.id) FROM import_batches ib WHERE ib.channel_id = rs.channel_id AND ib.status = 'validated')
      GROUP BY rs.channel_id, rs.sub_channel_id, sc.name, a.previous_period, a.current_period, a.max_known_day;
      CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel ON audit_revenue_by_sub_channel (channel_id, sub_channel_id);

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      SELECT ars.channel_id, ars.sub_channel_id, rs.establishment_id, e.company_id, c.cnpj, ars.max_known_day,
        SUM(CASE WHEN dr.period = ars.previous_period THEN dr.amount ELSE 0 END) AS previous_revenue,
        SUM(CASE WHEN dr.period = ars.current_period THEN dr.amount ELSE 0 END) AS current_revenue
      FROM audit_revenue_by_sub_channel ars
      JOIN revenue_snapshots rs ON rs.channel_id = ars.channel_id AND rs.sub_channel_id = ars.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id JOIN companies c ON c.id = e.company_id
      LEFT JOIN daily_revenues_consolidated dr ON dr.establishment_id = e.id AND dr.day <= ars.max_known_day
        AND dr.period IN (ars.previous_period, ars.current_period)
      GROUP BY ars.channel_id, ars.sub_channel_id, rs.establishment_id, e.company_id, c.cnpj, ars.max_known_day;
      CREATE UNIQUE INDEX index_audit_revenue_by_company ON audit_revenue_by_company (channel_id, establishment_id);

      CREATE MATERIALIZED VIEW audit_weekly_revenue AS
      SELECT channel_id, period, ((day - 1) / 7) + 1 AS week,
        SUM(amount) AS revenue, COUNT(DISTINCT establishment_id) AS establishments
      FROM daily_revenues_consolidated GROUP BY channel_id, period, ((day - 1) / 7) + 1;
      CREATE UNIQUE INDEX index_audit_weekly_revenue ON audit_weekly_revenue (channel_id, period, week);
    SQL
  end

  def down
    execute 'DROP MATERIALIZED VIEW IF EXISTS audit_weekly_revenue, audit_revenue_by_company, audit_revenue_by_sub_channel CASCADE'
  end
end
