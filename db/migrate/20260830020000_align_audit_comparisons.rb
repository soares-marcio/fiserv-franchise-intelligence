class AlignAuditComparisons < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP MATERIALIZED VIEW IF EXISTS audit_stalled_companies CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_company CASCADE;
      DROP MATERIALIZED VIEW IF EXISTS audit_revenue_by_sub_channel CASCADE;

      CREATE MATERIALIZED VIEW audit_revenue_by_sub_channel AS
      WITH periods AS (
        SELECT channel_id, competencia AS competencia_atual, max_dia_conhecido,
          (competencia - INTERVAL '1 month')::date AS competencia_m1
        FROM competencia_coverages
        WHERE NOT fechado
      )
      SELECT rs.channel_id, rs.sub_channel_id, sc.sub_canal,
        periods.competencia_m1, periods.competencia_atual, periods.max_dia_conhecido,
        COALESCE(SUM(dr.amount) FILTER (WHERE dr.competencia = periods.competencia_m1), 0)
          AS faturamento_m1,
        COALESCE(SUM(dr.amount) FILTER (WHERE dr.competencia = periods.competencia_atual), 0)
          AS faturamento_atual,
        COUNT(DISTINCT rs.establishment_id) FILTER (WHERE e.primary_establishment_id IS NULL)
          AS estabelecimentos_principais
      FROM revenue_snapshots rs
      JOIN sub_channels sc ON sc.id = rs.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id
      JOIN periods ON periods.channel_id = rs.channel_id
      LEFT JOIN daily_revenues_consolidated dr
        ON dr.channel_id = rs.channel_id
        AND dr.establishment_id = rs.establishment_id
        AND dr.competencia IN (periods.competencia_m1, periods.competencia_atual)
        AND dr.day <= periods.max_dia_conhecido
      WHERE rs.import_batch_id = (
        SELECT MAX(ib.id)
        FROM import_batches ib
        WHERE ib.channel_id = rs.channel_id
          AND ib.status = 'validated'
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots latest WHERE latest.import_batch_id = ib.id
          )
      )
      GROUP BY rs.channel_id, rs.sub_channel_id, sc.sub_canal,
        periods.competencia_m1, periods.competencia_atual, periods.max_dia_conhecido;
      CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel
        ON audit_revenue_by_sub_channel (channel_id, sub_channel_id);

      CREATE MATERIALIZED VIEW audit_revenue_by_company AS
      SELECT sub_channel.channel_id, sub_channel.sub_channel_id, e.company_id, c.cnpj,
        sub_channel.max_dia_conhecido, sub_channel.competencia_m1,
        sub_channel.competencia_atual,
        COALESCE(SUM(dr.amount) FILTER (
          WHERE dr.competencia = sub_channel.competencia_m1
        ), 0) AS faturamento_m1,
        COALESCE(SUM(dr.amount) FILTER (
          WHERE dr.competencia = sub_channel.competencia_atual
        ), 0) AS faturamento_atual
      FROM audit_revenue_by_sub_channel sub_channel
      JOIN revenue_snapshots rs
        ON rs.channel_id = sub_channel.channel_id
        AND rs.sub_channel_id = sub_channel.sub_channel_id
      JOIN establishments e ON e.id = rs.establishment_id
      JOIN companies c ON c.id = e.company_id
      LEFT JOIN daily_revenues_consolidated dr
        ON dr.channel_id = sub_channel.channel_id
        AND dr.establishment_id = rs.establishment_id
        AND dr.competencia IN (
          sub_channel.competencia_m1, sub_channel.competencia_atual
        )
        AND dr.day <= sub_channel.max_dia_conhecido
      WHERE rs.import_batch_id = (
        SELECT MAX(ib.id)
        FROM import_batches ib
        WHERE ib.channel_id = sub_channel.channel_id
          AND ib.status = 'validated'
          AND EXISTS (
            SELECT 1 FROM revenue_snapshots latest WHERE latest.import_batch_id = ib.id
          )
      )
      GROUP BY sub_channel.channel_id, sub_channel.sub_channel_id, e.company_id, c.cnpj,
        sub_channel.max_dia_conhecido, sub_channel.competencia_m1,
        sub_channel.competencia_atual;
      CREATE UNIQUE INDEX index_audit_revenue_by_company
        ON audit_revenue_by_company (channel_id, sub_channel_id, company_id);

      CREATE MATERIALIZED VIEW audit_stalled_companies AS
      WITH current_activity AS (
        SELECT company_view.channel_id, company_view.sub_channel_id, company_view.company_id,
          MAX(dr.day) AS last_sale_day
        FROM audit_revenue_by_company company_view
        JOIN establishments e ON e.company_id = company_view.company_id
          AND e.channel_id = company_view.channel_id
        JOIN daily_revenues_consolidated dr ON dr.establishment_id = e.id
          AND dr.channel_id = company_view.channel_id
          AND dr.competencia = company_view.competencia_atual
          AND dr.day <= company_view.max_dia_conhecido
        GROUP BY company_view.channel_id, company_view.sub_channel_id, company_view.company_id
      )
      SELECT company_view.channel_id, company_view.sub_channel_id, sc.sub_canal,
        company_view.company_id, company_view.cnpj, company_view.max_dia_conhecido,
        activity.last_sale_day,
        company_view.max_dia_conhecido - activity.last_sale_day AS dias_sem_venda,
        company_view.faturamento_m1, company_view.faturamento_atual
      FROM audit_revenue_by_company company_view
      JOIN current_activity activity
        ON activity.channel_id = company_view.channel_id
        AND activity.sub_channel_id = company_view.sub_channel_id
        AND activity.company_id = company_view.company_id
      JOIN sub_channels sc ON sc.id = company_view.sub_channel_id
      WHERE company_view.max_dia_conhecido - activity.last_sale_day >= 7;
      CREATE UNIQUE INDEX index_audit_stalled_companies
        ON audit_stalled_companies (channel_id, sub_channel_id, company_id);
    SQL
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
