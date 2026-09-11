# Exportação da página 3M de um MIC, onde a linha é o EC. Mesmo formato do arquivo por MIC —
# meses em M0/M1/M2 e a janela na nota —, mais o que só existe aqui: a data de credenciamento
# e quantos dos três meses da janela do EC já têm volume.
class ThreeMonthEstablishmentsExporter
  IDENTITY_HEADERS = [
    "EC", "Nome", "Credenciado em", "Meses apurados", "Digitalização",
    "Adicional sem antecipação", "Adicional com antecipação"
  ].freeze
  MONTH_HEADERS = %w[Débito Crédito Total].freeze

  def initialize(reports, window:, sub_channel_name:)
    @reports = reports
    @window = window
    @sub_channel_name = sub_channel_name
  end

  def headers
    IDENTITY_HEADERS + (0..2).flat_map { |index| MONTH_HEADERS.map { |label| "M#{index} #{label}" } }
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers:, rows: @reports.map { |report| export_row(report) },
      sheet_name: "Ganhos 3M por EC", note:)
  end

  def note
    janela = Array(@window).map { |period| I18n.l(period, format: "%m/%Y") }.join(" · ")
    "#{@sub_channel_name} · ECs credenciados na janela #{janela}"
  end

  def export_row(report)
    credenciamento = report[:accreditation] || {}
    [
      report[:ec],
      report[:trade_name] || report[:legal_name],
      date(credenciamento["accredited_on"]),
      credenciamento["months_observed"]&.to_i,
      credenciamento["digitalization_amount"]&.to_d,
      credenciamento["addon_without_auto"]&.to_d,
      credenciamento["addon_with_auto"]&.to_d,
      *report[:months].flat_map { |month| month_cells(month) }
    ]
  end

  def month_cells(month)
    return [ nil, nil, nil ] unless month[:covered]

    [ month[:debit].to_d, month[:credit].to_d, month[:total].to_d ]
  end

  def date(value)
    I18n.l(value.to_date) if value.present?
  end
end
