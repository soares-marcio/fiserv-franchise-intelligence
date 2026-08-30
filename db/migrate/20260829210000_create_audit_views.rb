class CreateAuditViews < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE MATERIALIZED VIEW audit_revenue_by_sub_channel AS
      WITH current_coverage AS (
        SELECT channel_id, competencia, max_dia_conhecido
        FROM competencia_coverages
        WHERE NOT fechado
      ), aligned AS (
        SELECT c.channel_id, c.competencia AS competencia_atual,
          c.max_dia_conhecido, (c.competencia - INTERVAL '1 month')::date AS competencia_m1
        FROM current_coverage c
      )
      SELECT rs.channel_id, rs.sub_channel_id, sc.sub_canal, a.competencia_m1, a.competencia_atual,
        a.max_dia_conhecido,
        COALESCE(SUM(CASE WHEN dr.competencia = a.competencia_m1 THEN dr.amount END), 0) AS faturamento_m1,
        COALESCE(SUM(CASE WHEN dr.competencia = a.competencia_atual THEN dr.amount END), 0) AS faturamento_atual,
        COUNT(DISTINCT rs.establishment_id) FILTER (WHERE e.primary_establishment_id IS NULL) AS estabelecimentos_principais
      FROM revenue_snapshots rs
      JOIN sub_channels sc ON sc.id = rs.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id
      JOIN aligned a ON a.channel_id = rs.channel_id
      LEFT JOIN daily_revenues_consolidated dr ON dr.establishment_id = rs.establishment_id
        AND dr.channel_id = rs.channel_id AND dr.competencia IN (a.competencia_m1, a.competencia_atual)
        AND dr.day <= a.max_dia_conhecido
      WHERE rs.import_batch_id = (SELECT MAX(ib.id) FROM import_batches ib WHERE ib.channel_id = rs.channel_id AND ib.status = 'validated')
      GROUP BY rs.channel_id, rs.sub_channel_id, sc.sub_canal, a.competencia_m1, a.competencia_atual, a.max_dia_conhecido;
      CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel ON audit_revenue_by_sub_channel (channel_id, sub_channel_id);

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      SELECT ars.channel_id, ars.sub_channel_id, rs.establishment_id, e.company_id, c.cnpj, ars.max_dia_conhecido,
        SUM(CASE WHEN dr.competencia = ars.competencia_m1 THEN dr.amount ELSE 0 END) AS faturamento_m1,
        SUM(CASE WHEN dr.competencia = ars.competencia_atual THEN dr.amount ELSE 0 END) AS faturamento_atual
      FROM audit_revenue_by_sub_channel ars
      JOIN revenue_snapshots rs ON rs.channel_id = ars.channel_id AND rs.sub_channel_id = ars.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id JOIN companies c ON c.id = e.company_id
      LEFT JOIN daily_revenues_consolidated dr ON dr.establishment_id = e.id AND dr.day <= ars.max_dia_conhecido
        AND dr.competencia IN (ars.competencia_m1, ars.competencia_atual)
      GROUP BY ars.channel_id, ars.sub_channel_id, rs.establishment_id, e.company_id, c.cnpj, ars.max_dia_conhecido;
      CREATE UNIQUE INDEX index_audit_revenue_by_company ON audit_revenue_by_company (channel_id, establishment_id);

      CREATE MATERIALIZED VIEW audit_weekly_revenue AS
      SELECT channel_id, competencia, ((day - 1) / 7) + 1 AS semana,
        SUM(amount) AS faturamento, COUNT(DISTINCT establishment_id) AS estabelecimentos
      FROM daily_revenues_consolidated GROUP BY channel_id, competencia, ((day - 1) / 7) + 1;
      CREATE UNIQUE INDEX index_audit_weekly_revenue ON audit_weekly_revenue (channel_id, competencia, semana);
    SQL
  end

  def down
    execute 'DROP MATERIALIZED VIEW IF EXISTS audit_weekly_revenue, audit_revenue_by_company, audit_revenue_by_sub_channel CASCADE'
  end
end
