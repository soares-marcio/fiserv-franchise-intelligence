require "test_helper"

class BinImport::ValidatorTest < ActiveSupport::TestCase
  test "rejects more than one REPORT_ID" do
    rows = {
      "Mapa de Clientes BIN" => [
        required_map.merge("REPORT_ID" => "1478", "EC" => "12345678"),
        required_map.merge("REPORT_ID" => "1479", "EC" => "12345679")
      ],
      "Faturamento" => [ required_revenue ],
      "Ativacao" => []
    }

    error = assert_raises(ArgumentError) { BinImport::Validator.new(rows).validate! }
    assert_equal "Arquivo deve conter exatamente um REPORT_ID", error.message
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
