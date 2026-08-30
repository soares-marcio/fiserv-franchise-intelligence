# Janela de comparação de um subcanal: qual competência está aberta e qual faixa de dias
# é comparável entre o mês atual e o anterior.
class CompetenciaWindow
  attr_reader :competencia_atual, :competencia_m1, :from_day, :to_day, :max_day

  def self.from_coverages(coverages, competencia: nil, from_day: nil, to_day: nil)
    selected = select_cover(coverages, competencia)
    return if selected.blank?

    max_day = selected["max_dia_conhecido"].to_i
    max_day = 31 if max_day < 1
    start_day = clamp_day(from_day, 1)
    end_day = clamp_day(to_day, max_day)
    new(competencia: selected["competencia"].to_date, from_day: start_day,
      to_day: [ end_day, start_day ].max, max_day:)
  end

  def self.select_cover(coverages, competencia)
    date = parse_month(competencia)
    match = coverages.find { |row| row["competencia"].to_date == date } if date
    match || coverages.find { |row| !row["fechado"] } || coverages.first
  end
  private_class_method :select_cover

  def self.parse_month(value)
    return if value.blank?

    (value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)).beginning_of_month
  rescue Date::Error, ArgumentError, TypeError
    nil
  end
  private_class_method :parse_month

  def self.clamp_day(value, fallback)
    day = value.to_i
    day.between?(1, 31) ? day : fallback
  end
  private_class_method :clamp_day

  def initialize(competencia:, from_day:, to_day:, max_day:)
    @competencia_atual = competencia
    @competencia_m1 = competencia.prev_month.beginning_of_month
    @from_day = from_day
    @to_day = to_day
    @max_day = max_day
  end

  def to_binds
    { competencia_atual:, competencia_m1:, from_day:, to_day: }
  end
end
