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

  def by_sub_channel
    rows = monthly_rows
    sub_channels = SubChannel.where(id: rows.map { |r| r["sub_channel_id"] }.uniq).index_by(&:id)
    open_periods = open_periods_by_channel

    rows.group_by { |r| r["sub_channel_id"] }.map do |sub_channel_id, sub_rows|
      sub_channel = sub_channels.fetch(sub_channel_id)
      months = build_months(sub_rows, open_periods)
      {
        sub_channel_id:, uuid: sub_channel.uuid, name: sub_channel.name,
        channel_id: sub_rows.first["channel_id"], months:,
        recurring_total: months.sum { |m| m[:recurring] },
        adjustment_total: months.sum { |m| m[:accelerator] - m[:reducer] }
      }
    end.sort_by { |row| row[:name] }
  end

  private

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
        SUM(map.net_mdr * (vol.debit + vol.credit)) FILTER (WHERE map.net_mdr IS NOT NULL)
          / NULLIF(SUM(vol.debit + vol.credit) FILTER (WHERE map.net_mdr IS NOT NULL), 0)
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

  def build_months(sub_rows, open_periods)
    previous_total = nil
    sub_rows.sort_by { |r| r["period"] }.map do |row|
      period = row["period"].to_date
      debit = row["debit"].to_f
      credit = row["credit"].to_f
      total = debit + credit
      net_mdr = row["weighted_net_mdr"]&.to_f
      rates = SubChannelCompensationRules.mdr_rates(net_mdr)
      recurring = rates ? debit * rates[:debit] + credit * rates[:credit] : 0.0
      adjustment = SubChannelCompensationRules.performance_adjustment(
        previous: previous_total, current: total, recurring: recurring
      )
      previous_total = total

      { period:, debit:, credit:, total:, net_mdr:, rates:, recurring:,
        partial: open_periods.include?([ row["channel_id"], period ]),
        mdr_fallback: row["mdr_fallback"] }.merge(adjustment)
    end
  end

  def open_periods_by_channel
    ApplicationRecord.connection.exec_query(
      "SELECT channel_id, period FROM period_coverages WHERE NOT closed"
    ).to_a.map { |row| [ row["channel_id"], row["period"].to_date ] }.to_set
  end
end
