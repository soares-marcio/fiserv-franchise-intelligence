# Exportação da listagem por subcanal: leva o recorte inteiro da tela — filtros, busca e
# aba —, menos a paginação. Exportar só a página entregaria um recorte que ninguém pediu.
class EstablishmentListingExporter
  include EstablishmentsHelper

  HEADERS = [
    "EC", "CNPJ", "Razão social", "Nome fantasia", "Status do contrato",
    "Credenciamento", "Ativação", "Suspensão", "Mês anterior (cheio)",
    "Mês anterior comparável", "Mês atual", "Variação alinhada %"
  ].freeze

  def initialize(rows, sub_channel_name:, window: nil)
    @rows = rows
    @sub_channel_name = sub_channel_name
    @window = window
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers: HEADERS, rows: @rows.map { |row| export_row(row) } + [ total_row ],
      sheet_name: "Estabelecimentos", note:)
  end

  def note
    return @sub_channel_name unless @window

    "#{@sub_channel_name} · mês anterior completo; comparação alinhada do dia " \
      "#{@window.from_day} ao #{@window.to_day}"
  end

  def export_row(row)
    previous = row["previous_revenue"].to_d
    current = row["current_revenue"].to_d
    [
      row["ec"], formatted_cnpj(row["cnpj"]), row["legal_name"], row["trade_name"],
      contract_status_label(row["contract_status"]),
      *%w[accredited_on activated_on suspended_on].map { |column| date(row[column]) },
      row["previous_full_revenue"].to_d, previous, current,
      AlignedVariation.percent(previous, current)
    ]
  end

  # Célula vazia, não o travessão da tela: quem abre no Excel filtra por vazio, não por "—".
  def date(value)
    I18n.l(value.to_date) if value.present?
  end

  def total_row
    previous = @rows.sum { |row| row["previous_revenue"].to_d }
    current = @rows.sum { |row| row["current_revenue"].to_d }
    [ "TOTAL", nil, nil, nil, nil, nil, nil, nil,
      @rows.sum { |row| row["previous_full_revenue"].to_d }, previous, current,
      AlignedVariation.percent(previous, current) ]
  end
end
