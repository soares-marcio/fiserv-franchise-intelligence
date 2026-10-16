# Idade do que o portal mostra, canal a canal: quando o último arquivo chegou e até que dia o
# faturamento dele vai. São duas perguntas diferentes, e o selo do cabeçalho tratava uma pela
# outra — em 16/09/2026 ele dizia "Arquivo há 2 dias" em verde porque o arquivo mais novo da
# carteira era o da Região Goiás, justamente o canal cujos dados param em 26 de agosto.
#
# O "geral" que o selo mostra é sempre o **pior** de cada sinal, nunca o mais recente: é a mesma
# regra do corte de período em ReportScope#cutoff_day — o observado não superestima a cobertura.
class FileFreshness
  # stale_sub_channels: MICs parados num Master que chega em mais de um arquivo — o arquivo
  # do Master pode estar em dia e um dos MICs não (AuditViews.current_snapshots_sql).
  Entry = Data.define(:name, :uuid, :received_at, :covered_on, :stale_sub_channels) do
    # O valor cru da consulta volta em UTC; sem converter, um arquivo recebido às 21h de
    # ontem já conta como de hoje e o selo diz um dia a menos que a tela de importação.
    def received_on = received_at&.in_time_zone&.to_date

    def received_days = received_on && (Date.current - received_on).to_i

    def covered_days = covered_on && (Date.current - covered_on).to_i

    # Sem arquivo ou sem cobertura conta como atrasado: a ausência não é um sinal verde.
    def received_stale? = received_days.nil? || received_days >= ImportBatch::STALE_AFTER_DAYS

    def covered_stale? = covered_days.nil? || covered_days >= ImportBatch::STALE_AFTER_DAYS
  end

  # Sem organização (a conta da plataforma) não há carteira a medir: nenhuma entrada.
  def initialize(organization:)
    @organization = organization
  end

  def self.call(organization:) = new(organization:).call

  def call = entries

  def entries
    @entries ||= rows.map do |row|
      Entry.new(
        name: row["name"], uuid: row["uuid"],
        received_at: row["received_at"],
        covered_on: coverage_date(row["period"], row["max_known_day"]),
        stale_sub_channels: stale_sub_channels.fetch(row["id"], [])
      )
    end
  end

  def received_days = entries.filter_map(&:received_days).max

  def covered_days = entries.filter_map(&:covered_days).max

  # A data que o selo escreve: a cobertura mais antiga entre os canais.
  def covered_on = entries.filter_map(&:covered_on).min

  def received_stale? = entries.empty? || entries.any?(&:received_stale?)

  def covered_stale? = entries.empty? || entries.any?(&:covered_stale?)

  def any_file? = entries.any? { |entry| entry.received_at.present? }

  # Os masters fora da janela, em qualquer um dos dois sinais. É o que a tela de importação
  # lista: o selo do topo diz que há defasagem, e aqui se descobre de quem é.
  def stale_entries = entries.select { |entry| entry.received_stale? || entry.covered_stale? }

  private

  # O dia coberto é dia do mês; a data sai da competência mais o deslocamento.
  def coverage_date(period, max_known_day)
    return if period.blank? || max_known_day.blank?

    period.to_date + (max_known_day.to_i - 1)
  end

  # Uma consulta só para os dois sinais. A tabela de cobertura tem uma linha por canal e
  # competência, e o LATERAL pega a competência mais recente de cada canal.
  #
  # Com o Master em mais de um arquivo, os dois sinais são do MIC mais atrasado: o arquivo
  # mais velho entre os MICs vigentes, e o menor corte entre eles na competência. Master sem
  # foto de MIC (lote sem faturamento) cai no último lote validado, como antes.
  def rows
    return [] if @organization.nil?

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, organization_id: @organization.id ])
      WITH #{sub_channel_files_sql}
      SELECT channel.id, channel.name, channel.uuid,
        COALESCE(
          (SELECT MIN(files.received_at) FROM sub_channel_files files WHERE files.channel_id = channel.id),
          (
            SELECT MAX(batch.created_at) FROM import_batches batch
            WHERE batch.channel_id = channel.id AND batch.status = 'validated'
          )
        ) AS received_at,
        coverage.period,
        LEAST(coverage.max_known_day, COALESCE((
          SELECT MIN(cover.max_known_day) FROM sub_channel_cover cover
          WHERE cover.channel_id = channel.id AND cover.period = coverage.period
        ), coverage.max_known_day)) AS max_known_day
      FROM channels channel
      LEFT JOIN LATERAL (
        SELECT period, max_known_day FROM period_coverages
        WHERE period_coverages.channel_id = channel.id
        ORDER BY period DESC
        LIMIT 1
      ) coverage ON TRUE
      WHERE channel.organization_id = :organization_id AND channel.deleted_at IS NULL
      ORDER BY channel.name
    SQL
    ApplicationRecord.connection.exec_query(sql).to_a
  end

  # MICs cujo último arquivo passou do prazo enquanto outro MIC do mesmo Master recebeu
  # arquivo em dia. Quando o Master inteiro está parado, o aviso é dele, não de cada MIC.
  def stale_sub_channels
    @stale_sub_channels ||= begin
      sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, organization_id: @organization&.id.to_i ])
        WITH #{sub_channel_files_sql}
        SELECT files.channel_id, sub_channel.name, files.received_at
        FROM sub_channel_files files
        JOIN sub_channels sub_channel ON sub_channel.id = files.sub_channel_id
        JOIN channels channel ON channel.id = files.channel_id
        WHERE channel.organization_id = :organization_id
        ORDER BY sub_channel.name
      SQL
      ApplicationRecord.connection.exec_query(sql).to_a.group_by { |row| row["channel_id"] }
        .transform_values { |rows| stale_names(rows) }
    end
  end

  def stale_names(rows)
    days = rows.to_h { |row| [ row["name"], (Date.current - row["received_at"].in_time_zone.to_date).to_i ] }
    return [] if days.values.all? { |age| age >= ImportBatch::STALE_AFTER_DAYS }

    days.select { |_name, age| age >= ImportBatch::STALE_AFTER_DAYS }.keys
  end

  # O último arquivo de cada MIC vigente e o corte de cada MIC (AuditViews). Arquivo é lote
  # vindo de planilha: o cadastro manual de um EC não diz que o MIC recebeu arquivo.
  def sub_channel_files_sql
    <<~SQL.strip
      #{AuditViews.current_snapshots_sql(channel_predicate: organization_channels).strip},
      #{AuditViews.sub_channel_cover_sql.strip},
      sub_channel_files AS (
        SELECT snapshot.channel_id, snapshot.sub_channel_id, MAX(ib.created_at) AS received_at
        FROM revenue_snapshots snapshot
        JOIN import_batches ib ON ib.id = snapshot.import_batch_id
        WHERE ib.status = 'validated' AND ib.source_filename <> '#{AuditViews::MANUAL_SOURCE}'
          AND (snapshot.channel_id, snapshot.sub_channel_id) IN (
            SELECT channel_id, sub_channel_id FROM sub_channel_cover
          )
        GROUP BY snapshot.channel_id, snapshot.sub_channel_id
      )
    SQL
  end

  def organization_channels
    "ib.channel_id IN (SELECT id FROM channels WHERE organization_id = :organization_id AND deleted_at IS NULL)"
  end
end
