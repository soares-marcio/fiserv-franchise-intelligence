# Exportação dos clientes que venderam num dia — o conteúdo do modal do calendário. A linha é
# o cliente (CNPJ), somando os ECs dele naquele dia, como no modal.
class DayCompaniesExporter
  HEADERS = [ "CNPJ", "Razão social", "MIC", "CNAE", "ECs com movimento", "Valor no dia" ].freeze

  def initialize(rows, date:)
    @rows = rows
    @date = date
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers: HEADERS, rows: @rows.map { |row| export_row(row) } + [ total_row ],
      sheet_name: "Clientes do dia",
      note: "CNPJs que venderam em #{I18n.l(@date)}, do maior valor para o menor")
  end

  def export_row(row)
    [
      ApplicationController.helpers.formatted_cnpj(row["cnpj"]),
      row["legal_name"], row["sub_channels"], row["cnaes"],
      row["establishments"].to_i, row["revenue"].to_d
    ]
  end

  def total_row
    [ "TOTAL", nil, nil, nil, @rows.sum { |row| row["establishments"].to_i },
      @rows.sum { |row| row["revenue"].to_d } ]
  end
end
