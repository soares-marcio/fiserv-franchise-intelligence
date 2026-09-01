class CreateAccreditationEarningsView < ActiveRecord::Migration[8.1]
  # Prêmio de entrada por EC, apurado na janela M0/M1/M2 a partir do credenciamento.
  # A marca d'água ("paga-se a diferença quando a faixa sobe") equivale à faixa do mês de
  # pico, porque as faixas são monotônicas no faturamento — por isso basta o MAX mensal.
  # Não depende das views alinhadas: lê map_snapshots e daily_revenues_consolidated direto.
  def up
    without_auto = SubChannelCompensationRules.accreditation_case_sql(
      "MAX(month_total) FILTER (WHERE month_covered)", with_auto: false
    )
    with_auto = SubChannelCompensationRules.accreditation_case_sql(
      "MAX(month_total) FILTER (WHERE month_covered)", with_auto: true
    )

    execute <<~SQL
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
          -- Classificação de antecipação automática só para destacar a hipótese provável:
          -- positiva com vocabulário conhecido, negativa quando preenchida sem ele, e NULL
          -- (indefinida) quando a planilha não trouxe nada. A tela sempre mostra os dois
          -- cenários; isto nunca decide o valor sozinho.
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
        -- Um mês só conta se houver cobertura registrada: fechado soma inteiro, aberto
        -- soma até o corte, sem cobertura fica fora — months_observed expõe a diferença
        -- entre "ganho zero" e "não apurável".
        SELECT a.channel_id, a.sub_channel_id, a.establishment_id, a.accredited_on,
          a.m0_period, a.has_app_access, a.auto_classified,
          months.month_index,
          (cover.channel_id IS NOT NULL) AS month_covered,
          COALESCE(SUM(revenue.amount) FILTER (
            WHERE cover.closed OR revenue.day <= cover.max_known_day
          ), 0) AS month_total
        FROM accredited a
        CROSS JOIN LATERAL (
          VALUES (a.m0_period, 0),
            ((a.m0_period + INTERVAL '1 month')::date, 1),
            ((a.m0_period + INTERVAL '2 months')::date, 2)
        ) AS months(period, month_index)
        LEFT JOIN period_coverages cover
          ON cover.channel_id = a.channel_id AND cover.period = months.period
        LEFT JOIN daily_revenues_consolidated revenue
          ON revenue.channel_id = a.channel_id
          AND revenue.establishment_id = a.establishment_id
          AND revenue.period = months.period
        GROUP BY a.channel_id, a.sub_channel_id, a.establishment_id, a.accredited_on,
          a.m0_period, a.has_app_access, a.auto_classified, months.month_index,
          cover.channel_id, cover.closed, cover.max_known_day
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

    # As views novas precisam do GRANT de leitura; NAMES já inclui esta.
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS audit_accreditation_earnings CASCADE"
  end
end
