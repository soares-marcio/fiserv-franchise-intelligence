# Indicadores do Anexo B por subcanal e competência. Cada mês é um fato próprio, como no
# recorrente, e as faixas vivem em SubChannelIndicatorRules.
#
# A base de cada mês vem do arquivo daquele mês: o Mapa importado com current_period igual à
# competência (o último, se houve vários). Sem arquivo da competência não há base, e os três
# indicadores que dependem dela ficam sem leitura — em vez de emprestar a base de outro mês,
# cujo ATIVO NO MÊS ATUAL? descreve outro mês. Com os arquivos semanais, o histórico se
# constrói sozinho.
#
# A base do mês são os ECs do Mapa daquela competência que não estavam suspensos antes de ela
# começar: o anexo fala em "base total de Estabelecimentos indicados", e um EC suspenso em
# junho não pode ser contado como inativo em agosto. Quem é suspenso durante o mês fica na
# base — é o numerador do descredenciamento. Medido em 17/09/2026 no MIC GOIANIA 4, agosto:
# 227 ECs no arquivo, 210 na base.
class SubChannelIndicatorsQuery
  INDICATORS = SubChannelIndicatorRules::INDICATORS.keys.freeze

  LATEST_MAP_BATCHES_SQL = <<~SQL.freeze
    SELECT ib.channel_id, MAX(ib.id) AS import_batch_id
    FROM import_batches ib
    WHERE ib.status = 'validated'
      AND EXISTS (SELECT 1 FROM map_snapshots m WHERE m.import_batch_id = ib.id)
    GROUP BY ib.channel_id
  SQL

  def initialize(channel_id: nil)
    @channel_id = channel_id
  end

  # Os insumos só mudam numa consolidação; o carimbo dela na chave invalida o cache sozinho.
  def by_sub_channel
    Rails.cache.fetch([ "indicators", PeriodCoverage.consolidation_stamp, @channel_id ]) do
      compute_by_sub_channel
    end
  end

  private

  def compute_by_sub_channel
    @accreditations = accreditations_by_month
    @proposals = proposals_by_month
    @bases = bases_by_month
    open_periods = open_periods_by_channel
    periods = periods_by_channel

    portfolio_sub_channels.map do |sub_channel|
      months = periods.fetch(sub_channel.channel_id, []).map do |period|
        partial = open_periods.include?([ sub_channel.channel_id, period ])
        { period:, partial:, readings: readings(sub_channel.id, period, partial:) }
      end
      { sub_channel_id: sub_channel.id, uuid: sub_channel.uuid, name: sub_channel.name,
        channel_id: sub_channel.channel_id, months:, **summarize(months) }
    end.sort_by { |row| row[:name] }
  end

  # Quem aparece em alguma das três fontes: credenciou, indicou ou tem base em algum mês.
  def portfolio_sub_channels
    ids = (@accreditations.keys + @proposals.keys + @bases.keys).map(&:first).uniq
    SubChannel.where(id: ids).order(:name)
  end

  # Competência aberta mostra o valor e não a leitura: um mês pela metade credencia menos
  # e transaciona menos por não ter terminado.
  def readings(sub_channel_id, period, partial:)
    key = [ sub_channel_id, period ]
    proposal = @proposals[key]
    base = @bases[key]
    {
      quality: reading(:quality, proposal, :rejected, :proposals, partial:, pending: proposal&.fetch(:pending)),
      accreditations: reading(:accreditations, { value: @accreditations.fetch(key, 0) }, :value, nil, partial:),
      volume: reading(:volume, base, :above_threshold, :base, partial:),
      attrition: reading(:attrition, base, :suspended, :base, partial:),
      activity: reading(:activity, base, :inactive, :base, partial:)
    }
  end

  def reading(indicator, source, numerator_key, denominator_key, partial:, **detail)
    return { value: nil, verdict: nil, **detail } unless source

    numerator = source.fetch(numerator_key)
    denominator = denominator_key && source.fetch(denominator_key)
    value = denominator ? numerator * 100.0 / denominator : numerator
    { value:, numerator:, denominator:,
      verdict: partial ? nil : SubChannelIndicatorRules.verdict(indicator, value), **detail }
  end

  # O retrato é o último mês fechado com leitura de cada indicador; a sequência em Risco
  # conta, dele para trás, os meses fechados seguidos em Risco — é a medida da cláusula
  # 12.2 (xx). Mês sem leitura interrompe a contagem: não se afirma continuidade sobre o
  # que não foi apurado.
  def summarize(months)
    closed = months.reject { |month| month[:partial] }.sort_by { |month| month[:period] }.reverse
    latest = {}
    risk_streaks = {}
    INDICATORS.each do |indicator|
      series = closed.map { |month| { period: month[:period], **month[:readings][indicator] } }
        .drop_while { |reading| reading[:verdict].nil? }
      latest[indicator] = series.first
      risk_streaks[indicator] = series.take_while { |reading| reading[:verdict] == :risk }.size
    end
    { latest:, risk_streaks:,
      risk_count: latest.count { |_, reading| reading && reading[:verdict] == :risk } }
  end

  # Credenciamentos do mês: ECs do último Mapa com DATA DE CREDENCIAMENTO na competência —
  # a mesma contagem que a tela 3M chama de "ECs no M0". O arquivo carrega a carteira
  # inteira com a data, então um mês sem credenciamento é zero de verdade, não ausência.
  def accreditations_by_month
    sql = sanitize(<<~SQL)
      SELECT map.sub_channel_id, date_trunc('month', map.accredited_on)::date AS period,
        COUNT(*) AS accredited
      FROM map_snapshots map
      JOIN (#{LATEST_MAP_BATCHES_SQL.indent(6).strip}) latest ON latest.import_batch_id = map.import_batch_id
      WHERE map.accredited_on IS NOT NULL
        AND (:channel_id IS NULL OR latest.channel_id = :channel_id)
      GROUP BY map.sub_channel_id, date_trunc('month', map.accredited_on)
    SQL
    rows(sql).to_h { |row| [ key_of(row), row["accredited"].to_i ] }
  end

  # Uma proposta aparece em todo arquivo que a traz, com o status daquele dia. Vale a última
  # versão de cada NR DA PROPOSTA, atribuída ao mês da DATA DA PROPOSTA: uma proposta de
  # julho pendente no arquivo de julho e recusada no de setembro conta como recusa de julho.
  # Medido em 17/09/2026: 122 propostas distintas em 417 linhas, nenhuma em dois MICs.
  def proposals_by_month
    sql = sanitize(<<~SQL)
      SELECT sub_channel_id, date_trunc('month', proposed_on)::date AS period,
        COUNT(*) AS proposals,
        COUNT(*) FILTER (WHERE proposal_status = :rejected) AS rejected,
        COUNT(*) FILTER (WHERE proposal_status = :pending) AS pending
      FROM (
        SELECT DISTINCT ON (proposal_number) sub_channel_id, proposed_on, proposal_status
        FROM activation_proposals
        WHERE (:channel_id IS NULL OR channel_id = :channel_id)
        ORDER BY proposal_number, import_batch_id DESC
      ) latest
      WHERE proposed_on IS NOT NULL
      GROUP BY sub_channel_id, date_trunc('month', proposed_on)
    SQL
    rows(sql).to_h do |row|
      [ key_of(row), { proposals: row["proposals"].to_i, rejected: row["rejected"].to_i,
        pending: row["pending"].to_i } ]
    end
  end

  # A base de cada competência e os três numeradores que saem dela. O vínculo EC → subcanal
  # vem do lote da época, como no recorrente. ATIVO NO MÊS ATUAL? é a declaração da própria
  # Fiserv e descreve exatamente o mês do arquivo; conferida contra o volume do mês em
  # 17/09/2026, concorda em 567 de 567 ECs no lote de setembro. O importador nunca grava
  # NULL nela (Normalizer.boolean); se gravasse, o IS FALSE não contaria o nulo como inativo.
  def bases_by_month
    binds = { channel_id: @channel_id, threshold: SubChannelIndicatorRules::VOLUME_THRESHOLD }
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, binds ])
      WITH map_batches AS (
        SELECT ib.channel_id, ib.current_period, MAX(ib.id) AS import_batch_id
        FROM import_batches ib
        WHERE ib.status = 'validated'
          AND EXISTS (SELECT 1 FROM map_snapshots m WHERE m.import_batch_id = ib.id)
        GROUP BY ib.channel_id, ib.current_period
      ), volumes AS (
        SELECT channel_id, establishment_id, period, SUM(amount) AS amount
        FROM monthly_volumes_consolidated
        WHERE metric IN ('debito', 'credito')
          AND (:channel_id IS NULL OR channel_id = :channel_id)
        GROUP BY channel_id, establishment_id, period
      )
      SELECT map.sub_channel_id, batch.current_period AS period,
        COUNT(*) AS base,
        COUNT(*) FILTER (WHERE map.suspended_on >= batch.current_period
          AND map.suspended_on < (batch.current_period + INTERVAL '1 month')) AS suspended,
        COUNT(*) FILTER (WHERE map.active_current_month IS FALSE) AS inactive,
        COUNT(*) FILTER (WHERE vol.amount > :threshold) AS above_threshold
      FROM map_batches batch
      JOIN map_snapshots map ON map.import_batch_id = batch.import_batch_id
      LEFT JOIN volumes vol
        ON vol.channel_id = batch.channel_id
        AND vol.establishment_id = map.establishment_id
        AND vol.period = batch.current_period
      WHERE (:channel_id IS NULL OR batch.channel_id = :channel_id)
        AND (map.suspended_on IS NULL OR map.suspended_on >= batch.current_period)
      GROUP BY map.sub_channel_id, batch.current_period
    SQL
    rows(sql).to_h do |row|
      [ key_of(row), { base: row["base"].to_i, suspended: row["suspended"].to_i,
        inactive: row["inactive"].to_i, above_threshold: row["above_threshold"].to_i } ]
    end
  end

  # Competências com volume mensal importado, por canal — o mesmo universo do recorrente.
  def periods_by_channel
    sql = sanitize(<<~SQL)
      SELECT DISTINCT channel_id, period FROM monthly_volumes_consolidated
      WHERE (:channel_id IS NULL OR channel_id = :channel_id)
      ORDER BY period
    SQL
    rows(sql).group_by { |row| row["channel_id"] }
      .transform_values { |group| group.map { |row| row["period"].to_date } }
  end

  def open_periods_by_channel
    rows("SELECT channel_id, period FROM period_coverages WHERE NOT closed")
      .map { |row| [ row["channel_id"], row["period"].to_date ] }.to_set
  end

  def key_of(row)
    [ row["sub_channel_id"], row["period"].to_date ]
  end

  def sanitize(sql)
    ApplicationRecord.sanitize_sql_array([ sql, { channel_id: @channel_id,
      rejected: SubChannelIndicatorRules::REJECTED_STATUS,
      pending: SubChannelIndicatorRules::PENDING_STATUS } ])
  end

  def rows(sql)
    ApplicationRecord.connection.exec_query(sql).to_a
  end
end
