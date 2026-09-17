class AddAutoFlexAndMonthlyParcelsToEarnings < ActiveRecord::Migration[8.1]
  # Duas mudanças na mesma view, vindas do Anexo C da Circular de Oferta de Franquia (v1.2023),
  # que é contrato assinado e fonte mais forte que os slides de onde o modelo saiu.
  #
  # 1. A modalidade de antecipação volta a ser classificada, agora por SOLUÇÕES FINANCEIRAS.
  #    A migração 20260901090000 tirou a classificação porque STATUS ANTECIP AUTO NO BOARDING
  #    não carregava o sinal, e na época as duas candidatas pareciam hipóteses concorrentes.
  #    O contrato mostra que não são: a coluna "C" é "com auto/flex" (modalidade contratada) e
  #    o volume antecipado é base de **outra** remuneração (1.1.2-B). SOLUÇÕES FINANCEIRAS traz
  #    exatamente o vocabulário do contrato e classifica 567 de 567 ECs.
  #
  # 2. A view passa a dizer **quanto se paga em qual mês**, e não só o total da janela. A regra
  #    do contrato é sequencial: M0 paga a faixa; M1 paga faixa(M1) − faixa(M0) se subiu; M2
  #    paga faixa(M2) − a maior entre as anteriores. A soma telescopa para a faixa do mês de
  #    pico — é por isso que o total continua idêntico, e é o que o invariante prova.
  #
  # addon_without_auto e addon_with_auto ficam intactos de propósito: é contra eles que a
  # reconciliação prova esta mudança. Redefini-los como soma das parcelas tornaria o teste
  # tautológico.
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
  # negativa.
  #
  # É agregado com FILTER, e não window function, por uma armadilha que não faz barulho: com
  # MAX(...) OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), o frame de M0 é vazio e
  # devolve NULL; faixa − NULL é NULL; e o GREATEST do Postgres **ignora nulos e devolve 0**.
  # O M0 pagaria zero, sem erro nenhum, e a view pareceria funcionar.
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
      ), accredited AS (
        SELECT snapshot.channel_id, snapshot.sub_channel_id, snapshot.establishment_id,
          snapshot.accredited_on,
          date_trunc('month', snapshot.accredited_on)::date AS m0_period,
          -- Prova de app baixado, confirmada como regra: o pagamento de digitalização
          -- só ocorre em M0 e só para EC com acesso ao app.
          (snapshot.last_app_access_at IS NOT NULL) AS has_app_access,
          -- Modalidade contratada, que escolhe a coluna do adicional. NULL é indefinido.
          (#{SubChannelCompensationRules.auto_flex_case_sql('snapshot.financial_solutions')})
            AS auto_flex
        FROM map_snapshots snapshot
        JOIN latest_map_batches latest ON latest.import_batch_id = snapshot.import_batch_id
        WHERE snapshot.accredited_on IS NOT NULL
      ), month_revenue AS (
        SELECT a.channel_id, a.sub_channel_id, a.establishment_id, a.accredited_on,
          a.m0_period, a.has_app_access, a.auto_flex,
          months.month_index, months.period,
          (volume.amount IS NOT NULL) AS month_covered,
          COALESCE(volume.amount, 0) AS month_total,
          -- amount é NOT NULL na tabela, então NULL aqui é ausência de linha — mês sem volume
          -- importado, nunca "faturou zero". A faixa sai do valor cru, para o contrato do
          -- accreditation_case_sql (NULL vira zero) valer sobre a ausência, e não sobre um
          -- zero que ninguém mediu.
          volume.amount AS observed_total
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
      ), month_bracket AS (
        SELECT channel_id, sub_channel_id, establishment_id, accredited_on, m0_period,
          has_app_access, auto_flex, month_index, month_covered, month_total,
          CASE
            WHEN auto_flex
              THEN #{SubChannelCompensationRules.accreditation_case_sql('observed_total', with_auto: true).indent(12).strip}
            ELSE #{SubChannelCompensationRules.accreditation_case_sql('observed_total', with_auto: false).indent(12).strip}
          END AS bracket_amount
        FROM month_revenue
      )
      SELECT channel_id, sub_channel_id, establishment_id, accredited_on, m0_period,
        has_app_access, auto_flex,
        COUNT(*) FILTER (WHERE month_covered) AS months_observed,
        MAX(month_total) FILTER (WHERE month_covered) AS peak_month_revenue,
        CASE
          WHEN bool_or(month_covered AND month_index = 0) AND has_app_access
            THEN #{format('%.2f', SubChannelCompensationRules::DIGITALIZATION_FEE)}
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
        has_app_access, auto_flex;

      CREATE UNIQUE INDEX index_audit_accreditation_earnings
        ON audit_accreditation_earnings (channel_id, sub_channel_id, establishment_id);
    SQL
  end
end
