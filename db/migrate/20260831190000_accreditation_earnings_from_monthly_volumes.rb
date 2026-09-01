class AccreditationEarningsFromMonthlyVolumes < ActiveRecord::Migration[8.1]
  # A janela M0/M1/M2 passa a ser apurada sobre o volume mensal, e não sobre o
  # faturamento diário. Duas razões: o card mostra as colunas de mês vindas de
  # monthly_volumes, e apurar a faixa no diário faria faturamento e prêmio discordarem
  # dentro da mesma caixa; e o diário cobre só duas competências, enquanto o volume
  # mensal cobre cinco — com o diário, EC credenciado antes de julho nunca apura.
  #
  # O volume mensal não tem dia, então não há corte: o mês do credenciamento já conta
  # cheio por regra ("fração de mês é considerada mês cheio") e os demais entram
  # inteiros. Janela ainda em curso aparece com months_observed < 3.
  def up
    execute "DROP MATERIALIZED VIEW IF EXISTS audit_accreditation_earnings CASCADE"
    execute create_sql
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def create_sql
    without_auto = SubChannelCompensationRules.accreditation_case_sql(
      "MAX(month_total) FILTER (WHERE month_covered)", with_auto: false
    )
    with_auto = SubChannelCompensationRules.accreditation_case_sql(
      "MAX(month_total) FILTER (WHERE month_covered)", with_auto: true
    )

    <<~SQL
      CREATE MATERIALIZED VIEW audit_accreditation_earnings AS
      WITH latest_map_batches AS (
        SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (SELECT 1 FROM map_snapshots m WHERE m.import_batch_id = ib.id)
        GROUP BY ib.channel_id
      ), accredited AS (
        SELECT snapshot.channel_id, snapshot.sub_channel_id, snapshot.establishment_id,
          snapshot.accredited_on,
          date_trunc('month', snapshot.accredited_on)::date AS m0_period,
          (snapshot.last_app_access_at IS NOT NULL) AS has_app_access,
          -- Classificação de antecipação automática só destaca a hipótese provável; a
          -- tela sempre mostra os dois cenários e admite indefinida.
          CASE
            WHEN upper(coalesce(snapshot.auto_advance_boarding_status, '')) IN ('SIM', 'ATIVO', 'TRUE')
              OR upper(coalesce(snapshot.auto_advance_boarding_status_2, '')) IN ('SIM', 'ATIVO', 'TRUE')
              THEN TRUE
            WHEN snapshot.auto_advance_boarding_status IS NOT NULL
              OR snapshot.auto_advance_boarding_status_2 IS NOT NULL
              THEN FALSE
            ELSE NULL
          END AS auto_classified
        FROM map_snapshots snapshot
        JOIN latest_map_batches latest ON latest.import_batch_id = snapshot.import_batch_id
        WHERE snapshot.accredited_on IS NOT NULL
      ), month_revenue AS (
        SELECT a.channel_id, a.sub_channel_id, a.establishment_id, a.accredited_on,
          a.m0_period, a.has_app_access, a.auto_classified,
          months.month_index, months.period,
          (volume.amount IS NOT NULL) AS month_covered,
          COALESCE(volume.amount, 0) AS month_total
        FROM accredited a
        CROSS JOIN LATERAL (
          VALUES (a.m0_period, 0),
            ((a.m0_period + INTERVAL '1 month')::date, 1),
            ((a.m0_period + INTERVAL '2 months')::date, 2)
        ) AS months(period, month_index)
        LEFT JOIN monthly_volumes_consolidated volume
          ON volume.channel_id = a.channel_id
          AND volume.establishment_id = a.establishment_id
          AND volume.period = months.period
          AND volume.metric = 'total'
      )
      SELECT channel_id, sub_channel_id, establishment_id, accredited_on, m0_period,
        has_app_access, auto_classified,
        COUNT(*) FILTER (WHERE month_covered) AS months_observed,
        MAX(month_total) FILTER (WHERE month_covered) AS peak_month_revenue,
        CASE
          WHEN bool_or(month_covered AND month_index = 0) AND has_app_access
            THEN #{format('%.2f', SubChannelCompensationRules::DIGITALIZATION_FEE)}
          ELSE 0
        END AS digitalization_amount,
        (#{without_auto}) AS addon_without_auto,
        (#{with_auto}) AS addon_with_auto
      FROM month_revenue
      GROUP BY channel_id, sub_channel_id, establishment_id, accredited_on, m0_period,
        has_app_access, auto_classified;

      CREATE UNIQUE INDEX index_audit_accreditation_earnings
        ON audit_accreditation_earnings (channel_id, sub_channel_id, establishment_id);
    SQL
  end
end
