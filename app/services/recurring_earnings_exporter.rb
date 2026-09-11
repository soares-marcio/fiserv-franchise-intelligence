# Exportação do ganho recorrente. A tela é um card por MIC com a série mensal dentro; o
# arquivo desmonta a série em linhas — uma por MIC e competência —, que é o formato que a
# planilha do usuário consegue somar e dinamizar. Nada é recalculado aqui.
class RecurringEarningsExporter
  HEADERS = [
    "MIC", "Competência", "Competência parcial", "Débito", "Crédito", "Net MDR %",
    "Net MDR de arquivo anterior", "Repasse", "Ajuste", "Ganho do mês"
  ].freeze

  def initialize(reports, channel_name: nil)
    @reports = reports
    @channel_name = channel_name
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers: HEADERS, rows: rows + [ total_row ],
      sheet_name: "Ganho recorrente",
      note: "Ganho recorrente mês a mês · #{@channel_name || 'todos os Masters'}")
  end

  def rows
    @reports.flat_map do |report|
      report[:months].map { |month| export_row(report, month) }
    end
  end

  # Célula vazia, não zero, para o que a tela mostra como travessão: "sem ajuste" e "sem Net
  # MDR daquele mês" não são valores, e no Excel zero entra na média.
  def export_row(report, month)
    ajuste = month[:accelerator] - month[:reducer]
    [
      report[:name],
      I18n.l(month[:period], format: "%m/%Y"),
      ("sim" if month[:partial]),
      month[:debit].to_d,
      month[:credit].to_d,
      month[:net_mdr]&.to_d,
      ("sim" if month[:mdr_fallback]),
      month[:recurring].to_d,
      (ajuste.to_d unless ajuste.zero?),
      (month[:recurring] + ajuste).to_d
    ]
  end

  def total_row
    meses = @reports.flat_map { |report| report[:months] }
    ajuste = meses.sum { |month| month[:accelerator] - month[:reducer] }
    [ "TOTAL", nil, nil, meses.sum { |month| month[:debit].to_d },
      meses.sum { |month| month[:credit].to_d }, nil, nil,
      meses.sum { |month| month[:recurring].to_d }, ajuste.to_d,
      meses.sum { |month| month[:recurring].to_d } + ajuste.to_d ]
  end
end
