class DropAnticipationClassificationFromEarnings < ActiveRecord::Migration[8.1]
  # Remove a classificação de antecipação da view. O campo usado, STATUS ANTECIP AUTO NO
  # BOARDING, não carrega esse sinal: na base real só aparece com "0" (296 ECs) ou vazio
  # (256), nenhum positivo — a regra classificava todo mundo como "sem antecipação" ou
  # "indefinido", e nunca "com". Manter a coluna seria manter um dado que aparenta
  # classificar sem classificar.
  #
  # A apuração segue devolvendo as duas hipóteses (addon_without_auto e addon_with_auto);
  # o que sai é só a pretensão de saber qual delas vale. Enquanto a fonte correta não for
  # definida, a tela mostra as duas sem eleger nenhuma.
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
          -- Prova de app baixado, confirmada como regra: o pagamento de digitalização
          -- só ocorre em M0 e só para EC com acesso ao app.
          (snapshot.last_app_access_at IS NOT NULL) AS has_app_access
        FROM map_snapshots snapshot
        JOIN latest_map_batches latest ON latest.import_batch_id = snapshot.import_batch_id
        WHERE snapshot.accredited_on IS NOT NULL
      ), month_revenue AS (
        SELECT a.channel_id, a.sub_channel_id, a.establishment_id, a.accredited_on,
          a.m0_period, a.has_app_access,
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
        has_app_access,
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
        has_app_access;

      CREATE UNIQUE INDEX index_audit_accreditation_earnings
        ON audit_accreditation_earnings (channel_id, sub_channel_id, establishment_id);
    SQL
  end
end
