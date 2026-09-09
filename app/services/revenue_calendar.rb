# Grade do mês para a tela de ritmo: uma linha por semana de calendário, começando no domingo
# — a convenção que o datepicker do projeto já usa.
#
# O que a grade precisa distinguir são três estados de célula, e é neles que mora a honestidade
# da tela:
#
#   fora    — dia de outra competência, nas bordas da grade;
#   sem dado— dia além da cobertura do arquivo. Não é "não vendeu": é "não sabemos";
#   coberto — dia que o arquivo cobre, com valor, zero inclusive.
#
# A distinção importa porque o mês corrente costuma estar coberto só até o dia de corte: em
# setembro de 2026, com dado até o dia 2, uma grade sem esse cuidado mostraria 28 células
# afirmando R$ 0,00.
class RevenueCalendar
  Cell = Struct.new(:date, :revenue, :establishments, :state, keyword_init: true) do
    def day = date.day
    def outside? = state == :outside
    def uncovered? = state == :uncovered
  end

  Week = Struct.new(:cells, :label, :revenue, :establishments, keyword_init: true)

  def initialize(period:, covered_days:, days:, weeks:)
    @period = period
    @covered_days = covered_days
    @days = days.index_by { |row| row["day"].to_i }
    @weeks = weeks.index_by { |row| row["week_start"].to_date }
  end

  def weeks
    @weeks_grid ||= (first_cell..last_cell).each_slice(7).map { |dates| build_week(dates) }
  end

  # Escala da intensidade: o maior dia do próprio mês. Normalizar por um teto fixo faria um
  # mês fraco parecer uniforme e um forte, saturado.
  def max_revenue
    @max_revenue ||= @days.values.map { |row| row["revenue"].to_d }.max || 0
  end

  private

  def first_cell = @period - @period.wday

  def last_cell
    last = @period.end_of_month
    last + (6 - last.wday)
  end

  def build_week(dates)
    aggregate = @weeks[dates.first]
    cells = dates.map { |date| build_cell(date) }
    Week.new(cells:, label: label_for(cells),
      revenue: aggregate && aggregate["revenue"].to_d,
      establishments: aggregate && aggregate["establishments"].to_i)
  end

  def build_cell(date)
    return Cell.new(date:, state: :outside) unless date.month == @period.month && date.year == @period.year
    return Cell.new(date:, state: :uncovered) if date.day > @covered_days

    row = @days[date.day]
    Cell.new(date:, state: :covered, revenue: row ? row["revenue"].to_d : 0.to_d,
      establishments: row ? row["establishments"].to_i : 0)
  end

  # Rótulo pela faixa de dias que a semana cobre na competência. É o que faz a linha curta se
  # explicar sozinha: "dia 1" e "30–31" dizem por que somam menos que as outras, onde
  # "semana 1" e "semana 5" sugeriam desempenho.
  def label_for(cells)
    dias = cells.reject(&:outside?).map(&:day)
    return if dias.empty?

    dias.first == dias.last ? "dia #{dias.first}" : "#{dias.first}–#{dias.last}"
  end
end
