# Exportação da listagem por subcanal: leva o recorte inteiro da tela — filtros, busca e
# aba —, menos a paginação. Exportar só a página entregaria um recorte que ninguém pediu.
class EstablishmentListingExporter
  include EstablishmentsHelper

  # A coluna do EC saiu junto com a linha por EC: o arquivo acompanha a tela, uma linha por
  # CNPJ com o faturamento de todos os ECs somado. No lugar dela vai o Net MDR, como texto e
  # não como número, porque o cliente com ECs de alíquotas positivas diferentes leva a faixa
  # ("0,42% a 2,53%") em vez de um dos dois valores.
  HEADERS = [
    "Net MDR", "CNPJ", "Razão social", "Nome fantasia", "Status do contrato",
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
      net_mdr(row), formatted_cnpj(row["cnpj"]), row["legal_name"], row["trade_name"],
      contract_status_label(row["contract_status"]),
      *%w[accredited_on activated_on suspended_on].map { |column| date(row[column]) },
      row["previous_full_revenue"].to_d, previous, current,
      AlignedVariation.percent(previous, current)
    ]
  end

  # O rótulo do Net MDR é de tela — trunca em duas casas e usa vírgula —, e o arquivo tem que
  # dizer a mesma coisa que a linha. Vem do helper em vez de uma segunda formatação aqui, que
  # divergiria na primeira mudança de regra.
  def net_mdr(row)
    ApplicationController.helpers.client_net_mdr_label(row["net_mdr_min"], row["net_mdr_max"])
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
