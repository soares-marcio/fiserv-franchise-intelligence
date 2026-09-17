# Série mensal do ganho recorrente por subcanal: cada competência é um fato próprio —
# alíquota da faixa de Net MDR daquele mês × faturamento daquele mês. Nunca se soma
# faturamento de meses para aplicar alíquota sobre o montante.
#
# O Net MDR de cada competência vem do último lote importado daquele mês; competências
# anteriores ao primeiro arquivo caem no lote mais antigo (mdr_fallback), rotuladas na
# tela. Com os arquivos semanais, o histórico de MDR se constrói sozinho.
class RecurringEarningsQuery
  def initialize(channel_id: nil)
    @channel_id = channel_id
  end

  # Os insumos só mudam numa consolidação; o carimbo dela na chave invalida o cache
  # sozinho, sem ninguém precisar lembrar de expirar.
  def by_sub_channel
    Rails.cache.fetch([ "recurring", PeriodCoverage.consolidation_stamp, @channel_id ]) do
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
  # e ancorado no lote da época. O vínculo EC → subcanal também vem do lote da época:
  # se um EC trocar de subcanal, cada mês fica com o dono que tinha na ocasião.
  def monthly_rows
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
      WITH map_batches AS (
        SELECT ib.channel_id, ib.current_period, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (SELECT 1 FROM map_snapshots m WHERE m.import_batch_id = ib.id)
        GROUP BY ib.channel_id, ib.current_period
      ), fallback_batches AS (
        SELECT channel_id, MIN(import_batch_id) AS import_batch_id
        FROM map_batches GROUP BY channel_id
      ), period_batches AS (
        SELECT periods.channel_id, periods.period,
          COALESCE(era.import_batch_id, fallback.import_batch_id) AS import_batch_id,
          (era.import_batch_id IS NULL) AS mdr_fallback
        FROM (SELECT DISTINCT channel_id, period FROM monthly_volumes_consolidated) periods
        JOIN fallback_batches fallback ON fallback.channel_id = periods.channel_id
        LEFT JOIN map_batches era
          ON era.channel_id = periods.channel_id AND era.current_period = periods.period
      ), volumes AS (
        SELECT v.channel_id, v.establishment_id, v.period,
          COALESCE(SUM(v.amount) FILTER (WHERE v.metric = 'debito'), 0) AS debit,
          COALESCE(SUM(v.amount) FILTER (WHERE v.metric = 'credito'), 0) AS credit
        FROM monthly_volumes_consolidated v
        WHERE (:channel_id IS NULL OR v.channel_id = :channel_id)
          AND v.metric IN ('debito', 'credito')
        GROUP BY v.channel_id, v.establishment_id, v.period
      )
      SELECT map.sub_channel_id, vol.channel_id, vol.period, batch.mdr_fallback,
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
      JOIN period_batches batch
        ON batch.channel_id = vol.channel_id AND batch.period = vol.period
      JOIN map_snapshots map
        ON map.import_batch_id = batch.import_batch_id
        AND map.establishment_id = vol.establishment_id
      GROUP BY map.sub_channel_id, vol.channel_id, vol.period, batch.mdr_fallback
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
        partial:, mdr_fallback: row["mdr_fallback"] }.merge(adjustment)
    end
  end

  # As parcelas do prêmio por subcanal e **competência de calendário**. A view as guarda
  # indexadas pela janela do EC (m0_period), então cada uma é deslocada para o mês em que é
  # paga: M0 e a digitalização no próprio m0_period, M1 no mês seguinte, M2 no subsequente.
  def accreditation_by_period
    return {} unless AuditViews.populated?("audit_accreditation_earnings")

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: @channel_id } ])
      SELECT sub_channel_id, period, SUM(amount) AS amount
      FROM (
        SELECT channel_id, sub_channel_id, m0_period AS period,
          COALESCE(digitalization_amount, 0) + COALESCE(m0_addon_amount, 0) AS amount
        FROM audit_accreditation_earnings
        UNION ALL
        SELECT channel_id, sub_channel_id, (m0_period + INTERVAL '1 month')::date,
          COALESCE(m1_addon_amount, 0)
        FROM audit_accreditation_earnings
        UNION ALL
        SELECT channel_id, sub_channel_id, (m0_period + INTERVAL '2 months')::date,
          COALESCE(m2_addon_amount, 0)
        FROM audit_accreditation_earnings
      ) parcels
      WHERE (:channel_id IS NULL OR channel_id = :channel_id)
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
