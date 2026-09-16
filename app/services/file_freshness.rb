# Idade do que o portal mostra, canal a canal: quando o último arquivo chegou e até que dia o
# faturamento dele vai. São duas perguntas diferentes, e o selo do cabeçalho tratava uma pela
# outra — em 16/09/2026 ele dizia "Arquivo há 2 dias" em verde porque o arquivo mais novo da
# carteira era o da Região Goiás, justamente o canal cujos dados param em 26 de agosto.
#
# O "geral" que o selo mostra é sempre o **pior** de cada sinal, nunca o mais recente: é a mesma
# regra do corte de período em ReportScope#cutoff_day — o observado não superestima a cobertura.
class FileFreshness
  Entry = Data.define(:name, :received_at, :covered_on) do
    # O valor cru da consulta volta em UTC; sem converter, um arquivo recebido às 21h de
    # ontem já conta como de hoje e o selo diz um dia a menos que a tela de importação.
    def received_on = received_at&.in_time_zone&.to_date

    def received_days = received_on && (Date.current - received_on).to_i

    def covered_days = covered_on && (Date.current - covered_on).to_i

    # Sem arquivo ou sem cobertura conta como atrasado: a ausência não é um sinal verde.
    def received_stale? = received_days.nil? || received_days >= ImportBatch::STALE_AFTER_DAYS

    def covered_stale? = covered_days.nil? || covered_days >= ImportBatch::STALE_AFTER_DAYS
  end

  def self.call = new.call

  def call = entries

  def entries
    @entries ||= rows.map do |row|
      Entry.new(
        name: row["name"],
        received_at: row["received_at"],
        covered_on: coverage_date(row["period"], row["max_known_day"])
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
  def rows
    ApplicationRecord.connection.exec_query(<<~SQL).to_a
      SELECT channel.name,
        (
          SELECT MAX(batch.created_at) FROM import_batches batch
          WHERE batch.channel_id = channel.id AND batch.status = 'validated'
        ) AS received_at,
        coverage.period, coverage.max_known_day
      FROM channels channel
      LEFT JOIN LATERAL (
        SELECT period, max_known_day FROM period_coverages
        WHERE period_coverages.channel_id = channel.id
        ORDER BY period DESC
        LIMIT 1
      ) coverage ON TRUE
      ORDER BY channel.name
    SQL
  end
end
