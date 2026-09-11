# Exportação do Clover Capital: as mesmas linhas da tela, com o recorte de MIC que estiver
# aplicado. A tela é a fonte — o arquivo não recalcula nada e não traz coluna que ela não
# mostre.
class PreapprovedOffersExporter
  # O MIC abre o arquivo porque é por ele que se recorta a tela, e a anotação fica de fora:
  # ela é texto livre com anexos, e uma célula de planilha não é onde se lê isso.
  HEADERS = [
    "MIC", "CNPJ", "Razão social", "ECs no CNPJ", "Volume pré-aprovado",
    "Prazo pré-aprovado (meses)", "Taxa pré-aprovada %"
  ].freeze

  def initialize(rows, sub_channel_name: nil)
    @rows = rows
    @sub_channel_name = sub_channel_name
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers: HEADERS, rows: @rows.map { |row| export_row(row) } + [ total_row ],
      sheet_name: "Clover Capital", note:)
  end

  def note
    "Ofertas pré-aprovadas da aba Mapa de Clientes BIN · " \
      "#{@sub_channel_name || 'todas as MICs com oferta'}"
  end

  def export_row(row)
    [
      row["sub_channels"],
      ApplicationController.helpers.formatted_cnpj(row["cnpj"]),
      row["legal_name"],
      row["establishments"].to_i,
      row["preapproved_volume"].to_d,
      row["preapproved_term"]&.to_i,
      row["preapproved_rate"]&.to_d
    ]
  end

  # Só o que é somável entra no total: prazo e taxa de clientes diferentes não se somam nem
  # se mediam — a média delas não descreve oferta nenhuma. Célula vazia, não zero.
  def total_row
    [ "TOTAL", nil, nil, @rows.sum { |row| row["establishments"].to_i },
      @rows.sum { |row| row["preapproved_volume"].to_d }, nil, nil ]
  end
end
