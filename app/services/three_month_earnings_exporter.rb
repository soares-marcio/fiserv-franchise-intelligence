# Exportação da página 3M por MIC. A tela é um card por MIC com o prêmio de entrada em cima e
# a matriz de três meses por três modalidades embaixo; o arquivo põe tudo na mesma linha, com
# os meses rotulados M0/M1/M2 e a janela escrita na nota do cabeçalho.
class ThreeMonthEarningsExporter
  # As duas colunas de adicional existem porque a fonte da antecipação não está definida: o
  # projeto apresenta o intervalo em vez de escolher uma hipótese. Ver CLAUDE.md.
  IDENTITY_HEADERS = [
    "MIC", "ECs no M0", "Digitalização", "Adicional sem antecipação",
    "Adicional com antecipação", "Prêmio mínimo", "Prêmio máximo"
  ].freeze
  MONTH_HEADERS = %w[Débito Crédito Total].freeze

  def initialize(reports, window:, channel_name: nil)
    @reports = reports
    @window = window
    @channel_name = channel_name
  end

  def headers
    IDENTITY_HEADERS + (0..2).flat_map { |index| MONTH_HEADERS.map { |label| "M#{index} #{label}" } }
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers:, rows: @reports.map { |report| export_row(report) },
      sheet_name: "Ganhos 3M", note:)
  end

  # A janela precisa estar escrita: M0/M1/M2 sem os meses não dizem de quando é o arquivo.
  def note
    janela = Array(@window).map { |period| I18n.l(period, format: "%m/%Y") }.join(" · ")
    "Prêmio de entrada e faturamento da janela #{janela} · #{@channel_name || 'todos os Masters'}"
  end

  def export_row(report)
    prize = report[:prize]
    digitalizacao = prize[:digitalization].to_d
    [
      report[:name], prize[:accredited].to_i, digitalizacao,
      prize[:addon_without_auto].to_d, prize[:addon_with_auto].to_d,
      digitalizacao + prize[:addon_without_auto].to_d,
      digitalizacao + prize[:addon_with_auto].to_d,
      *report[:months].flat_map { |month| month_cells(month) }
    ]
  end

  # Mês sem cobertura sai vazio, não zerado: "não sabemos" não é "não faturou" — a mesma
  # distinção que a tela faz com o travessão.
  def month_cells(month)
    return [ nil, nil, nil ] unless month[:covered]

    [ month[:debit].to_d, month[:credit].to_d, month[:total].to_d ]
  end
end
