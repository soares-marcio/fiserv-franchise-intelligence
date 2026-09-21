require "test_helper"

class BinImport::ValidatorTest < ActiveSupport::TestCase
  test "recusa mais de um REPORT_ID" do
    rows = {
      "Mapa de Clientes BIN" => [
        required_map.merge("REPORT_ID" => "1478", "EC" => "12345678"),
        required_map.merge("REPORT_ID" => "1479", "EC" => "12345679")
      ],
      "Faturamento" => [ required_revenue ],
      "Ativacao" => []
    }

    error = assert_raises(ArgumentError) { BinImport::Validator.new(rows).validate! }
    assert_match(/REPORT_ID/, error.message)
    assert_match(/separe as carteiras em arquivos diferentes/, error.message)
  end

  # O arquivo de 20/09/2026 trazia um EC em duas linhas iguais do Mapa e a tela mostrava o
  # erro do Postgres. Quem tem o arquivo na mão precisa saber o EC, as linhas e se basta apagar uma.
  test "recusa EC repetido no Mapa dizendo as linhas e que são idênticas" do
    rows = {
      "Mapa de Clientes BIN" => [
        required_map.merge("_row_number" => 38),
        required_map.merge("_row_number" => 39)
      ],
      "Faturamento" => [ required_revenue ],
      "Ativacao" => []
    }

    error = assert_raises(ArgumentError) { BinImport::Validator.new(rows).validate! }
    assert_match(/O EC 12345678 aparece 2 vezes na aba Mapa de Clientes BIN/, error.message)
    assert_match(/linhas 38 e 39/, error.message)
    assert_match(/idênticas: deixe uma e apague as outras/, error.message)
  end

  test "recusa EC repetido no Mapa dizendo em que colunas as linhas diferem" do
    rows = {
      "Mapa de Clientes BIN" => [
        required_map.merge("_row_number" => 38, "SUB-CANAL" => "MIC A"),
        required_map.merge("_row_number" => 40, "SUB-CANAL" => "MIC B", "STATUS DO CONTRATO" => "Closed")
      ],
      "Faturamento" => [ required_revenue ],
      "Ativacao" => []
    }

    error = assert_raises(ArgumentError) { BinImport::Validator.new(rows).validate! }
    assert_match(/linhas 38 e 40/, error.message)
    assert_match(/diferem em SUB-CANAL e STATUS DO CONTRATO/, error.message)
    assert_match(/confira na origem/, error.message)
  end

  private

  def required_map
    {
      "REPORT_ID" => "1478", "CANAL" => "MASTER", "SUB-CANAL" => "MIC",
      "EC" => "12345678", "CNPJ" => "12345678000195", "STATUS DO CONTRATO" => "Active"
    }
  end

  def required_revenue
    {
      "CANAL" => "MASTER", "SUB-CANAL" => "MIC", "EC" => "12345678",
      "CNPJ" => "12345678000195", "STATUS DO CONTRATO" => "Active"
    }
  end
end
