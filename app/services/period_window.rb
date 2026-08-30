# Janela de comparação de um subcanal: qual competência está aberta e qual faixa de dias
# é comparável entre o mês atual e o anterior.
class PeriodWindow
  attr_reader :current_period, :previous_period, :from_day, :to_day, :max_day

  def self.from_coverages(coverages, period: nil, from_day: nil, to_day: nil)
    selected = select_cover(coverages, period)
    return if selected.blank?

    max_day = selected["max_known_day"].to_i
    max_day = 31 if max_day < 1
    start_day = clamp_day(from_day, 1)
    end_day = clamp_day(to_day, max_day)
    new(period: selected["period"].to_date, from_day: start_day,
      to_day: [ end_day, start_day ].max, max_day:)
  end

  def self.select_cover(coverages, period)
    date = parse_month(period)
    match = coverages.find { |row| row["period"].to_date == date } if date
    match || coverages.find { |row| !row["closed"] } || coverages.first
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

  def initialize(period:, from_day:, to_day:, max_day:)
    @current_period = period
    @previous_period = period.prev_month.beginning_of_month
    @from_day = from_day
    @to_day = to_day
    @max_day = max_day
  end

  def to_binds
    { current_period:, previous_period:, from_day:, to_day: }
  end
end
