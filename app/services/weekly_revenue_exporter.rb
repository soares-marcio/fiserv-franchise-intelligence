# Exportação do ritmo do mês. A tela é uma grade de calendário; o arquivo é a mesma coisa em
# linhas, um dia por linha, com a semana ao lado para quem quiser dinamizar por semana.
#
# Só entram os dias que o arquivo cobre. Dia além da cobertura não vira linha zerada: zero ali
# afirmaria que a carteira não vendeu, quando o que há é ausência de dado — a mesma distinção
# que a grade faz com a célula "sem dado".
class WeeklyRevenueExporter
  HEADERS = [ "Semana", "Dia", "Data", "Faturamento", "ECs com movimento" ].freeze

  def initialize(calendar, period:, channel_name: nil)
    @calendar = calendar
    @period = period
    @channel_name = channel_name
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(headers: HEADERS, rows: rows + [ total_row ], sheet_name: "Ritmo do mês",
      note: "Faturamento diário de #{I18n.l(@period, format: '%m/%Y')} · " \
        "#{@channel_name || 'todos os Masters'} · só os dias cobertos pelo arquivo")
  end

  def rows
    @rows ||= @calendar.weeks.flat_map do |week|
      week.cells.reject { |cell| cell.outside? || cell.uncovered? }.map do |cell|
        [ week.label, cell.day, I18n.l(cell.date), cell.revenue.to_d, cell.establishments.to_i ]
      end
    end
  end

  # O total de ECs não é soma: o mesmo EC vende em vários dias e seria contado uma vez por
  # dia. A tela diz "ECs distintos" no rodapé da semana; aqui a célula fica vazia para o
  # arquivo não afirmar um número que ninguém apurou.
  def total_row
    [ "TOTAL", nil, nil, rows.sum { |row| row[3] }, nil ]
  end
end
