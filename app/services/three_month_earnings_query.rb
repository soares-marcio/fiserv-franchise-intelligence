# Cálculo ao vivo da página 3M: o usuário escolhe a janela de 3 meses, então nada aqui é
# materializado — os insumos (monthly_volumes_consolidated, map_snapshots) já estão
# persistidos pelo import e este objeto só faz a aritmética do modelo de remuneração.
class ThreeMonthEarningsQuery
  # O sub-canal de um EC vive nos snapshots por lote, não em establishments; o lote mais
  # recente validado com revenue_snapshots é o mesmo critério das views de auditoria.
  LATEST_BATCHES_SQL = <<~SQL.freeze
    latest_batches AS (
      SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
      FROM import_batches ib
      WHERE ib.status = 'validated'
        AND EXISTS (SELECT 1 FROM revenue_snapshots s WHERE s.import_batch_id = ib.id)
      GROUP BY ib.channel_id
    ),
    latest_map_batches AS (
      SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
      FROM import_batches ib
      WHERE ib.status = 'validated'
        AND EXISTS (SELECT 1 FROM map_snapshots m WHERE m.import_batch_id = ib.id)
      GROUP BY ib.channel_id
    ),
    members AS (
      SELECT snapshot.channel_id, snapshot.sub_channel_id, snapshot.establishment_id
      FROM revenue_snapshots snapshot
      JOIN latest_batches latest ON latest.import_batch_id = snapshot.import_batch_id
      WHERE (:channel_id IS NULL OR snapshot.channel_id = :channel_id)
    )
  SQL

  def initialize(periods:, channel_id: nil)
    @periods = periods.sort
    @channel_id = channel_id
  end

  # Meses com volume mensal disponível — a lista real, não a suposta: o seletor oferece
  # exatamente as competências que os arquivos importados trouxeram.
  def self.available_periods(channel_id: nil)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { channel_id: } ])
      SELECT DISTINCT period FROM monthly_volumes_consolidated
      WHERE (:channel_id IS NULL OR channel_id = :channel_id)
      ORDER BY period DESC
    SQL
    ApplicationRecord.connection.exec_query(sql).rows.map { |(period)| period.to_date }
  end

  def by_sub_channel
    volumes = volume_rows(group: "m.sub_channel_id")
    mdr = weighted_mdr_rows
    sub_channels = SubChannel.where(id: volumes.map { |r| r["sub_channel_id"] }.uniq).index_by(&:id)
    coverages = coverage_by_channel

    volumes.group_by { |r| r["sub_channel_id"] }.map do |sub_channel_id, rows|
      sub_channel = sub_channels.fetch(sub_channel_id)
      build_row(
        rows:, weighted_net_mdr: mdr[sub_channel_id], coverages:,
        identity: {
          sub_channel_id:, uuid: sub_channel.uuid, name: sub_channel.name,
          channel_id: rows.first["channel_id"]
        }
      )
    end.sort_by { |row| row[:name] }
  end

  # Só os ECs cujo M0 é o mês escolhido: assim M0, M1 e M2 significam a mesma coisa em
  # todos os cards, e a janela da tela é exatamente a janela de apuração deles.
  def by_establishment(sub_channel_id:)
    accreditations = accreditation_rows(sub_channel_id:)
    accredited_in_window = accreditations.select { |_, row| row["m0_period"].to_date == @periods.first }
    return [] if accredited_in_window.empty?

    volumes = volume_rows(group: "m.sub_channel_id, m.establishment_id", sub_channel_id:)
      .select { |row| accredited_in_window.key?(row["establishment_id"]) }
    mdr = weighted_mdr_rows(sub_channel_id:)
    coverages = coverage_by_channel
    establishments = Establishment.where(id: volumes.map { |r| r["establishment_id"] }.uniq)
      .includes(:current_map_snapshot, :company).index_by(&:id)

    volumes.group_by { |r| r["establishment_id"] }.map do |establishment_id, rows|
      establishment = establishments.fetch(establishment_id)
      build_row(
        rows:, weighted_net_mdr: mdr[sub_channel_id], coverages:,
        identity: {
          establishment_id:, ec: establishment.ec,
          trade_name: establishment.current_map_snapshot&.trade_name,
          legal_name: establishment.current_map_snapshot&.legal_name,
          channel_id: rows.first["channel_id"]
        }
      ).merge(accreditation: accreditations[establishment_id])
    end.sort_by { |row| row[:ec].to_s }
  end

  private

  def volume_rows(group:, sub_channel_id: nil)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, bind_params(sub_channel_id:) ])
      WITH #{LATEST_BATCHES_SQL}
      SELECT m.channel_id, #{group}, v.period,
        COALESCE(SUM(v.amount) FILTER (WHERE v.metric = 'debito'), 0) AS debit,
        COALESCE(SUM(v.amount) FILTER (WHERE v.metric = 'credito'), 0) AS credit
      FROM members m
      JOIN monthly_volumes_consolidated v
        ON v.channel_id = m.channel_id AND v.establishment_id = m.establishment_id
        AND v.period IN (:p0, :p1, :p2)
      WHERE (:sub_channel_id IS NULL OR m.sub_channel_id = :sub_channel_id)
      GROUP BY m.channel_id, #{group}, v.period
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  # Média dos net_mdr dos ECs ponderada pelo volume da janela. EC sem MDR (status
  # "Inativo") sai do numerador e do denominador: como zero, puxaria a carteira de faixa.
  def weighted_mdr_rows(sub_channel_id: nil)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, bind_params(sub_channel_id:) ])
      WITH #{LATEST_BATCHES_SQL},
      weights AS (
        SELECT m.channel_id, m.sub_channel_id, m.establishment_id, SUM(v.amount) AS volume
        FROM members m
        JOIN monthly_volumes_consolidated v
          ON v.channel_id = m.channel_id AND v.establishment_id = m.establishment_id
          AND v.period IN (:p0, :p1, :p2) AND v.metric IN ('debito', 'credito')
        WHERE (:sub_channel_id IS NULL OR m.sub_channel_id = :sub_channel_id)
        GROUP BY m.channel_id, m.sub_channel_id, m.establishment_id
      )
      SELECT w.sub_channel_id,
        SUM(map.net_mdr * w.volume) FILTER (WHERE map.net_mdr IS NOT NULL)
          / NULLIF(SUM(w.volume) FILTER (WHERE map.net_mdr IS NOT NULL), 0) AS weighted_net_mdr
      FROM weights w
      JOIN latest_map_batches latest ON latest.channel_id = w.channel_id
      LEFT JOIN map_snapshots map ON map.import_batch_id = latest.import_batch_id
        AND map.establishment_id = w.establishment_id
      GROUP BY w.sub_channel_id
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
      .to_h { |row| [ row["sub_channel_id"], row["weighted_net_mdr"]&.to_f ] }
  end

  def accreditation_rows(sub_channel_id:)
    return {} unless AuditViews.populated?("audit_accreditation_earnings")

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, { sub_channel_id: } ])
      SELECT * FROM audit_accreditation_earnings WHERE sub_channel_id = :sub_channel_id
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a.index_by { |row| row["establishment_id"] }
  end

  def coverage_by_channel
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, bind_params(sub_channel_id: nil) ])
      SELECT channel_id, period, closed FROM period_coverages
      WHERE period IN (:p0, :p1, :p2) AND (:channel_id IS NULL OR channel_id = :channel_id)
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
      .to_h { |row| [ [ row["channel_id"], row["period"].to_date ], row["closed"] ] }
  end

  def bind_params(sub_channel_id:)
    { channel_id: @channel_id, sub_channel_id:,
      p0: @periods[0], p1: @periods[1], p2: @periods[2] }
  end

  # Monta a linha final: um mês por período (mesmo sem volume), a faixa única de MDR da
  # carteira, o repasse por mês e os ajustes de performance nas duas transições da janela.
  def build_row(rows:, weighted_net_mdr:, coverages:, identity:)
    by_period = rows.index_by { |r| r["period"].to_date }
    channel_id = identity[:channel_id]
    months = @periods.map do |period|
      row = by_period[period]
      closed = coverages[[ channel_id, period ]]
      { period:, debit: row&.fetch("debit").to_f, credit: row&.fetch("credit").to_f,
        covered: !row.nil?, partial: closed == false }
    end

    rates = SubChannelCompensationRules.mdr_rates(weighted_net_mdr)
    months.each do |month|
      month[:total] = month[:debit] + month[:credit]
      month[:recurring] = rates ? month[:debit] * rates[:debit] + month[:credit] * rates[:credit] : 0.0
    end

    transitions = months.each_cons(2).map do |from, to|
      adjustment = SubChannelCompensationRules.performance_adjustment(
        previous: from[:total], current: to[:total], recurring: to[:recurring]
      )
      { from: from[:period], to: to[:period], partial: to[:partial] || from[:partial] }.merge(adjustment)
    end

    identity.merge(
      months:, weighted_net_mdr:, rates:, transitions:,
      recurring_total: months.sum { |m| m[:recurring] },
      accelerator_total: transitions.sum { |t| t[:accelerator] },
      reducer_total: transitions.sum { |t| t[:reducer] },
      total: months.sum { |m| m[:recurring] } +
        transitions.sum { |t| t[:accelerator] } - transitions.sum { |t| t[:reducer] }
    )
  end
end
