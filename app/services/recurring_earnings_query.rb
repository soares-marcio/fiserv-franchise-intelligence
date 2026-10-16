# Série mensal do ganho recorrente por subcanal: cada competência é um fato próprio —
# alíquota da faixa de Net MDR daquele mês × faturamento daquele mês. Nunca se soma
# faturamento de meses para aplicar alíquota sobre o montante.
#
# O Net MDR de cada competência é o **realizado**, e a Fiserv o publica no arquivo do mês
# seguinte: o NET MDR do Mapa é o MDR líquido (MDR − interchange, sobre o faturamento) do
# mês anterior ao do arquivo. Provado contra o extrato de agosto/2026 do MIC GOIANIA 4: o
# arquivo de setembro reproduz o realizado de agosto em 110 de 112 CNPJs (|Δ| < 0,01 pp), e
# os arquivos de agosto, idênticos entre si, não são o realizado de agosto — que carregam
# julho é inferência da regra, a confirmar com o extrato de julho. O primeiro arquivo do mês
# ainda assenta (97 de 112 em 03/09); do segundo em diante está fechado — daí o último lote.
#
# Por isso a competência P ancora no último lote com current_period = P + 1 mês (closed).
# Enquanto ele não chega, P usa o próprio arquivo — que traz o MDR de P − 1 — e fica marcada
# como provisional; competências anteriores ao primeiro arquivo caem no lote mais antigo
# (fallback). Ancorar no arquivo de P custou um repasse zerado: agosto/2026 do GOIANIA 4
# saía a 0,2489%, abaixo do degrau de 0,25%, quando o realizado era 0,2947%.
class RecurringEarningsQuery
  include ScopedQuery

  def initialize(scope:)
    @scope = scope
  end

  # Os insumos só mudam numa consolidação; o carimbo dela na chave invalida o cache
  # sozinho, sem ninguém precisar lembrar de expirar.
  def by_sub_channel
    Rails.cache.fetch([ "recurring", PeriodCoverage.consolidation_stamp, @scope.cache_key ]) do
      compute_by_sub_channel
    end
  end

  private

  def compute_by_sub_channel
    rows = monthly_rows
    accreditation = accreditation_by_period
    sub_channels = SubChannel.where(id: rows.map { |r| r["sub_channel_id"] }.uniq).index_by(&:id)
    open_periods = open_periods_by_channel

    rows.group_by { |r| r["sub_channel_id"] }.map do |sub_channel_id, sub_rows|
      sub_channel = sub_channels.fetch(sub_channel_id)
      months = build_months(sub_rows, open_periods, accreditation)
      {
        sub_channel_id:, uuid: sub_channel.uuid, name: sub_channel.name,
        channel_id: sub_rows.first["channel_id"], months:,
        recurring_total: months.sum { |m| m[:recurring] },
        accreditation_total: months.sum { |m| m[:accreditation] },
        adjustment_total: months.sum { |m| m[:accelerator] - m[:reducer] }
      }
    end.sort_by { |row| row[:name] }
  end

  # Uma linha por subcanal × competência, com o MDR ponderado pelo volume do próprio mês
  # e ancorado no lote do mês seguinte, que é onde o realizado do mês aparece. O vínculo
  # EC → subcanal vem do mesmo lote: ele já traz os ECs credenciados no mês, e se um EC
  # trocar de subcanal, cada mês fica com o dono que tinha na ocasião.
  def monthly_rows
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, scope_binds ])
      WITH #{@scope.partial? ? @scope.establishments_cte + "," : ""}
      #{AuditViews.current_snapshots_sql(table: "map_snapshots", by_period: true,
        name: "current_period_snapshots").strip},
      map_periods AS (
        SELECT map.id, map.channel_id, map.sub_channel_id, map.establishment_id,
          current.current_period
        FROM current_period_snapshots current
        JOIN map_snapshots map ON map.id = current.id
      ), sub_channel_periods AS (
        SELECT DISTINCT channel_id, sub_channel_id, current_period FROM map_periods
      ), fallback_periods AS (
        SELECT channel_id, sub_channel_id, MIN(current_period) AS current_period
        FROM sub_channel_periods GROUP BY channel_id, sub_channel_id
      ), period_sources AS (
        -- A âncora é escolhida por MIC: com o Master em mais de um arquivo, cada MIC tem os
        -- próprios lotes, e o arquivo de P + 1 de um MIC não diz nada sobre o outro.
        SELECT periods.channel_id, fallback.sub_channel_id, periods.period,
          COALESCE(closed.current_period, own.current_period, fallback.current_period)
            AS source_period,
          CASE
            WHEN closed.current_period IS NOT NULL THEN 'closed'
            WHEN own.current_period IS NOT NULL THEN 'provisional'
            ELSE 'fallback'
          END AS mdr_source
        FROM (SELECT DISTINCT channel_id, period FROM monthly_volumes_consolidated) periods
        JOIN fallback_periods fallback ON fallback.channel_id = periods.channel_id
        LEFT JOIN sub_channel_periods closed
          ON closed.channel_id = periods.channel_id
          AND closed.sub_channel_id = fallback.sub_channel_id
          AND closed.current_period = (periods.period + INTERVAL '1 month')::date
        LEFT JOIN sub_channel_periods own
          ON own.channel_id = periods.channel_id
          AND own.sub_channel_id = fallback.sub_channel_id
          AND own.current_period = periods.period
      ), volumes AS (
        SELECT v.channel_id, v.establishment_id, v.period,
          COALESCE(SUM(v.amount) FILTER (WHERE v.metric = 'debito'), 0) AS debit,
          COALESCE(SUM(v.amount) FILTER (WHERE v.metric = 'credito'), 0) AS credit
        FROM monthly_volumes_consolidated v
        WHERE #{establishment_predicate("v")}
          AND v.metric IN ('debito', 'credito')
        GROUP BY v.channel_id, v.establishment_id, v.period
      )
      SELECT map.sub_channel_id, vol.channel_id, vol.period, source.mdr_source,
        SUM(vol.debit) AS debit, SUM(vol.credit) AS credit,
        -- "Net MDR da carteira (sem Flex)" é o cabeçalho da tabela de recorrência do Anexo C.
        -- A leitura adotada: fora da média os ECs da modalidade Flex, e não "sem a parcela
        -- Flex das transações" — o contrato não desambigua, e o arquivo não separa transação
        -- por modalidade. São 2 ECs na base real, efeito numérico desprezível; o que vale é a
        -- regra estar escrita onde ela age.
        SUM(map.net_mdr * (vol.debit + vol.credit))
          FILTER (WHERE map.net_mdr IS NOT NULL AND BTRIM(map.financial_solutions) IS DISTINCT FROM 'Flex')
          / NULLIF(SUM(vol.debit + vol.credit)
            FILTER (WHERE map.net_mdr IS NOT NULL AND BTRIM(map.financial_solutions) IS DISTINCT FROM 'Flex'), 0)
          AS weighted_net_mdr
      FROM volumes vol
      JOIN period_sources source
        ON source.channel_id = vol.channel_id AND source.period = vol.period
      JOIN map_periods current
        ON current.channel_id = vol.channel_id
        AND current.sub_channel_id = source.sub_channel_id
        AND current.current_period = source.source_period
        AND current.establishment_id = vol.establishment_id
      JOIN map_snapshots map ON map.id = current.id
      GROUP BY map.sub_channel_id, vol.channel_id, vol.period, source.mdr_source
      ORDER BY vol.period
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  # O contrato compara "mês contra mês" (Anexo C, 1.1.3), e isso é competência de calendário,
  # não linha anterior da série: com um buraco de competência, comparar linhas faria junho
  # medir-se contra abril. E competência **aberta** não recebe ajuste — um mês pela metade
  # parece queda por não ter terminado, e o redutor incidiria sobre dado incompleto.
  def build_months(sub_rows, open_periods, accreditation)
    by_period = sub_rows.index_by { |row| row["period"].to_date }

    sub_rows.sort_by { |r| r["period"] }.map do |row|
      period = row["period"].to_date
      debit = row["debit"].to_f
      credit = row["credit"].to_f
      total = debit + credit
      net_mdr = row["weighted_net_mdr"]&.to_f
      rates = SubChannelCompensationRules.mdr_rates(net_mdr)
      recurring = rates ? debit * rates[:debit] + credit * rates[:credit] : 0.0
      # A parcela de credenciamento que cai nesta competência entra na base do ajuste: o
      # contrato manda o redutor incidir sobre a Participação, não só sobre a recorrência.
      parcel = accreditation.fetch([ row["sub_channel_id"], period ], 0.0)
      partial = open_periods.include?([ row["channel_id"], period ])
      previous = by_period[period.prev_month]
      previous_total = previous && !partial ? previous["debit"].to_f + previous["credit"].to_f : nil
      adjustment = SubChannelCompensationRules.performance_adjustment(
        previous: previous_total, current: total, participation: recurring + parcel
      )

      { period:, debit:, credit:, total:, net_mdr:, rates:, recurring:, accreditation: parcel,
        partial:, mdr_source: row["mdr_source"] }.merge(adjustment)
    end
  end

  # As parcelas do prêmio por subcanal e **competência de calendário**. A view as guarda
  # indexadas pela janela do EC (m0_period), então cada uma é deslocada para o mês em que é
  # paga: M0 no próprio m0_period, M1 no mês seguinte, M2 no subsequente — e a digitalização
  # no mês do primeiro acesso ao app (digitalization_period), como no extrato da Fiserv.
  def accreditation_by_period
    return {} unless AuditViews.populated?("audit_accreditation_earnings")

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, scope_binds ])
      SELECT sub_channel_id, period, SUM(amount) AS amount
      FROM (
        SELECT channel_id, sub_channel_id, m0_period AS period, COALESCE(m0_addon_amount, 0) AS amount
        FROM audit_accreditation_earnings
        UNION ALL
        SELECT channel_id, sub_channel_id, digitalization_period, digitalization_amount
        FROM audit_accreditation_earnings
        WHERE digitalization_amount > 0
        UNION ALL
        SELECT channel_id, sub_channel_id, (m0_period + INTERVAL '1 month')::date,
          COALESCE(m1_addon_amount, 0)
        FROM audit_accreditation_earnings
        UNION ALL
        SELECT channel_id, sub_channel_id, (m0_period + INTERVAL '2 months')::date,
          COALESCE(m2_addon_amount, 0)
        FROM audit_accreditation_earnings
      ) parcels
      WHERE #{channel_predicate}
      GROUP BY sub_channel_id, period
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a.to_h do |row|
      [ [ row["sub_channel_id"], row["period"].to_date ], row["amount"].to_f ]
    end
  end

  def open_periods_by_channel
    ApplicationRecord.connection.exec_query(
      "SELECT channel_id, period FROM period_coverages WHERE NOT closed"
    ).to_a.map { |row| [ row["channel_id"], row["period"].to_date ] }.to_set
  end
end
