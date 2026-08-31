require "csv"
require "caxlsx"

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

  def to_csv
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << HEADERS
      @rows.each { |row| csv << csv_row(row) }
      csv << total_csv_row
    end
  end

  def to_xlsx
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Auditoria") do |sheet|
      sheet.add_row [
        "Mês anterior completo; comparação alinhada com o mês atual até o dia #{@cutoff_day}"
      ]
      sheet.add_row HEADERS
      @rows.each { |row| sheet.add_row csv_row(row) }
      sheet.add_row total_csv_row
    end
    package.to_stream.read
  end

  private

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

  def variation(previous, current)
    return nil if previous.zero?

    ((current / previous - 1) * 100).round(1)
  end
end
