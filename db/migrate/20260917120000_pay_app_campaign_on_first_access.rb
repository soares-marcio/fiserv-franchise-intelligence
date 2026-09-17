class PayAppCampaignOnFirstAccess < ActiveRecord::Migration[8.1]
  # A digitalização (Campanha APP BIN) passa a seguir o extrato da Fiserv, e não a letra do
  # Anexo C. O extrato de agosto/2026 do MIC GOIANIA 4 pagou R$ 30 a 21 CNPJs: 14 da safra
  # de agosto e 7 da de julho — todos com primeiro acesso ao app em agosto. A regra é **por
  # CNPJ, no mês do primeiro acesso**; o portal a limita à janela do credenciamento (M0–M2),
  # que é o prazo do fator no Anexo C (1.1) — decisão do usuário em 17/09/2026.
  #
  # O arquivo traz "ULTIMO ACESSO NO APP", que sobrescreve. O primeiro acesso só é conhecido
  # quando os lotes mostram o CNPJ **sem** acesso antes de mostrá-lo com acesso: aí o menor
  # valor observado é o primeiro acesso. Se o CNPJ já aparece com acesso no primeiro lote em
  # que aparece, o primeiro acesso pode ser anterior a tudo que foi importado — medido:
  # sem essa distinção a view pagaria 39 CNPJs em agosto no GOIANIA 4, e 20 deles a Fiserv já
  # tinha pago em meses anteriores. Nesse caso a campanha cai em M0, a letra do Anexo C. Com
  # os arquivos semanais a transição passa a ser vista, e a regra se corrige sozinha. Fica um
  # limite: a coluna atrasa ~3 dias, e um acesso na virada do mês pode cair no mês seguinte —
  # foi o caso de 2 dos 21 CNPJs do extrato.
  #
  # A view ganha digitalization_period (mês em que a campanha cai, pago ou não) e deixa de
  # exigir volume em M0 para pagar: a campanha é do app, não do faturamento. As demais
  # colunas ficam como estão — é contra elas que a reconciliação segue provando as parcelas.
  def up
    execute "DROP MATERIALIZED VIEW IF EXISTS audit_accreditation_earnings CASCADE"
    execute create_sql
    # O DROP leva o GRANT do metabase_ro junto, e schema_integrity_test confere o privilégio.
    MetabaseRole.ensure! if MetabaseRole.role_exists?
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def peak_sql(with_auto:)
    SubChannelCompensationRules.accreditation_case_sql(
      "MAX(month_total) FILTER (WHERE month_covered)", with_auto:
    )
  end

  # Parcela do mês: a faixa alcançada nele menos a maior faixa já paga nos anteriores, nunca
  # negativa. Agregado com FILTER, e não window function: com um frame vazio em M0 o
  # GREATEST do Postgres ignoraria o NULL e devolveria 0 — o M0 pagaria zero, sem erro.
  def parcel_sql(index)
    reached = "COALESCE(MAX(bracket_amount) FILTER (WHERE month_index = #{index}), 0)"
    return reached if index.zero?

    paid = "COALESCE(MAX(bracket_amount) FILTER (WHERE month_index < #{index}), 0)"
    "GREATEST(#{reached} - #{paid}, 0)"
  end

  # Indefinido não vira zero: EC sem modalidade conhecida devolve NULL nas parcelas e no total
  # resolvido, e a tela volta a mostrar o intervalo só para ele.
  def undefined_guard(expression)
    "CASE WHEN auto_flex IS NULL THEN NULL ELSE #{expression} END"
  end

  def create_sql
    <<~SQL
      CREATE MATERIALIZED VIEW audit_accreditation_earnings AS
      WITH latest_map_batches AS (
        SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (SELECT 1 FROM map_snapshots m WHERE m.import_batch_id = ib.id)
        GROUP BY ib.channel_id
      ), first_app_access AS (
        -- O menor "último acesso" do CNPJ em qualquer lote, de qualquer EC dele — e se o
        -- CNPJ foi visto sem acesso antes de ser visto com acesso. Sem essa transição o
        -- primeiro acesso pode ser anterior ao primeiro lote importado.
        SELECT e.company_id,
          MIN(m.last_app_access_at) AS first_app_access_at,
          MIN(m.import_batch_id) FILTER (WHERE m.last_app_access_at IS NOT NULL)
            > MIN(m.import_batch_id) AS transition_observed
        FROM map_snapshots m
        JOIN establishments e ON e.id = m.establishment_id
        GROUP BY e.company_id
        HAVING bool_or(m.last_app_access_at IS NOT NULL)
      ), accredited AS (
        SELECT snapshot.channel_id, snapshot.sub_channel_id, snapshot.establishment_id,
          e.company_id, snapshot.accredited_on,
          date_trunc('month', snapshot.accredited_on)::date AS m0_period,
          (access.company_id IS NOT NULL) AS has_app_access,
          CASE
            WHEN access.company_id IS NULL THEN NULL
            WHEN access.transition_observed
              THEN date_trunc('month', access.first_app_access_at)::date
            ELSE date_trunc('month', snapshot.accredited_on)::date
          END AS digitalization_period,
          -- Modalidade contratada, que escolhe a coluna do adicional. NULL é indefinido.
          (#{SubChannelCompensationRules.auto_flex_case_sql('snapshot.financial_solutions')})
            AS auto_flex
        FROM map_snapshots snapshot
        JOIN latest_map_batches latest ON latest.import_batch_id = snapshot.import_batch_id
        JOIN establishments e ON e.id = snapshot.establishment_id
        LEFT JOIN first_app_access access ON access.company_id = e.company_id
        WHERE snapshot.accredited_on IS NOT NULL
      ), campaign_payer AS (
        -- Uma vez por CNPJ: o EC credenciado primeiro é quem carrega os R$ 30.
        SELECT DISTINCT ON (company_id) company_id, establishment_id
        FROM accredited
        ORDER BY company_id, accredited_on, establishment_id
      ), campaign AS (
        SELECT a.*,
          COALESCE(payer.establishment_id = a.establishment_id
            AND a.digitalization_period BETWEEN a.m0_period
              AND (a.m0_period + INTERVAL '2 months')::date, FALSE) AS pays_campaign
        FROM accredited a
        LEFT JOIN campaign_payer payer ON payer.company_id = a.company_id
      ), month_revenue AS (
        SELECT a.channel_id, a.sub_channel_id, a.establishment_id, a.accredited_on,
          a.m0_period, a.has_app_access, a.auto_flex, a.digitalization_period, a.pays_campaign,
          months.month_index, months.period,
          (volume.amount IS NOT NULL) AS month_covered,
          COALESCE(volume.amount, 0) AS month_total,
          -- amount é NOT NULL na tabela, então NULL aqui é ausência de linha — mês sem volume
          -- importado, nunca "faturou zero". A faixa sai do valor cru, para o contrato do
          -- accreditation_case_sql (NULL vira zero) valer sobre a ausência, e não sobre um
          -- zero que ninguém mediu.
          volume.amount AS observed_total
        FROM campaign a
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
      ), month_bracket AS (
        SELECT channel_id, sub_channel_id, establishment_id, accredited_on, m0_period,
          has_app_access, auto_flex, digitalization_period, pays_campaign,
          month_index, month_covered, month_total,
          CASE
            WHEN auto_flex
              THEN #{SubChannelCompensationRules.accreditation_case_sql('observed_total', with_auto: true).indent(12).strip}
            ELSE #{SubChannelCompensationRules.accreditation_case_sql('observed_total', with_auto: false).indent(12).strip}
          END AS bracket_amount
        FROM month_revenue
      )
      SELECT channel_id, sub_channel_id, establishment_id, accredited_on, m0_period,
        has_app_access, auto_flex, digitalization_period,
        COUNT(*) FILTER (WHERE month_covered) AS months_observed,
        MAX(month_total) FILTER (WHERE month_covered) AS peak_month_revenue,
        CASE
          WHEN pays_campaign THEN #{format('%.2f', SubChannelCompensationRules::DIGITALIZATION_FEE)}
          ELSE 0
        END AS digitalization_amount,
        (#{peak_sql(with_auto: false)}) AS addon_without_auto,
        (#{peak_sql(with_auto: true)}) AS addon_with_auto,
        CASE
          WHEN auto_flex THEN (#{peak_sql(with_auto: true)})
          WHEN NOT auto_flex THEN (#{peak_sql(with_auto: false)})
        END AS addon_amount,
        #{undefined_guard(parcel_sql(0))} AS m0_addon_amount,
        #{undefined_guard(parcel_sql(1))} AS m1_addon_amount,
        #{undefined_guard(parcel_sql(2))} AS m2_addon_amount
      FROM month_bracket
      GROUP BY channel_id, sub_channel_id, establishment_id, accredited_on, m0_period,
        has_app_access, auto_flex, digitalization_period, pays_campaign;

      CREATE UNIQUE INDEX index_audit_accreditation_earnings
        ON audit_accreditation_earnings (channel_id, sub_channel_id, establishment_id);
    SQL
  end
end
