require "test_helper"

# As mensagens de erro do import são lidas por quem tem o arquivo na mão e precisa consertá-lo
# sozinho. Cada uma tem que dizer três coisas: onde, o que está errado e o que fazer.
class ErrorMessagesTest < ActiveSupport::TestCase
  # A planilha da Fiserv ganha colunas com o tempo. Coluna a mais não pode recusar o arquivo:
  # o importador lê as células pelo nome do cabeçalho, então o que sobra é ignorado. Coluna
  # que falta — ou que foi renomeada, que aparece como falta e sobra ao mesmo tempo —
  # continua sendo erro.
  test "coluna nova na planilha não recusa o arquivo" do
    path = workbook_with_extra_column("ELEGIBILIDADE D0")

    assert_nothing_raised { BinImport::Importer.new(path, source_filename: "BIN_TESTE_20260811.xlsx").call }
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "coluna ausente diz qual é, em que aba, e o que fazer" do
    path = workbook_without_column("STATUS DO CONTRATO")

    erro = assert_raises(ArgumentError) do
      BinImport::Importer.new(path, source_filename: "BIN_TESTE_20260811.xlsx").call
    end

    assert_match "Mapa de Clientes BIN", erro.message
    assert_match "STATUS DO CONTRATO", erro.message
    assert_match(/renomeada|removida/i, erro.message, "a mensagem precisa dizer o que verificar")
    assert_no_match(/ausentes: ;/, erro.message, "lista vazia não pode aparecer na mensagem")
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  private

  def workbook_with_extra_column(header)
    escrever do |sheet_name, headers, rows|
      next [ headers, rows ] unless sheet_name == "Mapa de Clientes BIN"

      [ headers + [ header ], rows.map { |row| row.merge(header => "SIM") } ]
    end
  end

  def workbook_without_column(header)
    escrever do |sheet_name, headers, rows|
      next [ headers, rows ] unless sheet_name == "Mapa de Clientes BIN"

      [ headers - [ header ], rows ]
    end
  end

  # Escreve a planilha sintética deixando o bloco ajustar cabeçalhos e linhas de cada aba.
  def escrever
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-BIN_TESTE_20260811.xlsx")
    lojas = BinWorkbook.default_lojas
    Axlsx::Package.new do |package|
      BinWorkbook.sheet_rows(lojas).each do |sheet_name, rows|
        headers, rows = yield(sheet_name, BinWorkbook.headers_for(sheet_name, BinImport::Template::DEFAULT_VOLUME_MONTHS), rows)
        package.workbook.add_worksheet(name: sheet_name) do |worksheet|
          worksheet.add_row headers
          rows.each { |row| worksheet.add_row headers.map { |header| row[header] } }
        end
      end
      package.serialize(path.to_s)
    end
    path
  end
end
