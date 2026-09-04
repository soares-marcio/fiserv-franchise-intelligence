require "csv"
require "caxlsx"

# Mecânica das exportações: as duas telas que exportam gravam a mesma coisa em CSV e XLSX,
# mudando só as colunas, o nome da aba e a nota do cabeçalho da planilha.
class TabularExporter
  def initialize(headers:, rows:, sheet_name:, note: nil)
    @headers = headers
    @rows = rows
    @sheet_name = sheet_name
    @note = note
  end

  def to_csv
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << @headers
      @rows.each { |row| csv << row }
    end
  end

  def to_xlsx
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: @sheet_name) do |sheet|
      sheet.add_row [ @note ] if @note
      sheet.add_row @headers
      @rows.each { |row| sheet.add_row row }
    end
    package.to_stream.read
  end
end
