class ReportsExporter
  HEADERS = [
    "Sub-canal", "Dia de corte atual", "Mês anterior (cheio)",
    "Mês anterior comparável", "Mês atual", "Variação alinhada %"
  ].freeze

  def initialize(rows, cutoff_day:, totals: nil)
    @rows = rows
    @cutoff_day = cutoff_day
    @totals = totals
  end

  def to_csv = tabular.to_csv

  def to_xlsx = tabular.to_xlsx

  private

  def tabular
    TabularExporter.new(
      headers: HEADERS, rows: @rows.map { |row| csv_row(row) } + [ total_csv_row ],
      sheet_name: "Auditoria",
      note: "Mês anterior completo; comparação alinhada com o mês atual até o dia #{@cutoff_day}"
    )
  end

  def csv_row(row)
    previous = row["previous_revenue"].to_d
    previous_full = row["previous_full_revenue"].to_d
    current = row["current_revenue"].to_d
    [
      row["sub_channel_name"],
      row["max_known_day"],
      previous_full,
      previous,
      current,
      variation(previous, current)
    ]
  end

  def total_csv_row
    previous = (@totals || {})[:previous_revenue] || @rows.sum { |row| row["previous_revenue"].to_d }
    previous_full = (@totals || {})[:previous_full_revenue] ||
      @rows.sum { |row| row["previous_full_revenue"].to_d }
    current = (@totals || {})[:current_revenue] || @rows.sum { |row| row["current_revenue"].to_d }
    [ "TOTAL", @cutoff_day, previous_full, previous, current, variation(previous, current) ]
  end

  def variation(previous, current) = AlignedVariation.percent(previous, current)
end
