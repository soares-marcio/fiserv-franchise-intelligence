require "test_helper"

class Operations::RegisterManuallyTest < ActiveSupport::TestCase
  test "creates a client with the same identity rules as import" do
    batch = Operations::RegisterManually.call(valid_attrs)

    assert_equal "validated", batch.status
    establishment = Establishment.find_by(ec: "12345678")
    snapshot = establishment.current_map_snapshot
    assert_equal "12345678000195", establishment.company.cnpj
    assert_equal "MASTER", establishment.channel.name
    assert_equal "RUA TESTE 10", snapshot.street_address
    assert_equal "5611201", snapshot.cnae_code
    assert_equal "MIC TESTE", snapshot.sub_channel.name
  end

  test "grava razão social e nome fantasia sem inverter" do
    Operations::RegisterManually.call(valid_attrs)
    snapshot = Establishment.find_by!(ec: "12345678").current_map_snapshot

    assert_equal "RAZAO", snapshot.legal_name
    assert_equal "FANTASIA", snapshot.trade_name
  end

  test "propaga os nomes para o snapshot de faturamento" do
    Operations::RegisterManually.call(valid_attrs.merge(
      "previous_period" => "2026-07-01", "current_period" => "2026-08-01",
      "current_month_total" => "100", "day_01" => "100"
    ))
    snapshot = RevenueSnapshot.joins(:establishment).find_by!(establishments: { ec: "12345678" })

    assert_equal "RAZAO", snapshot.legal_name
    assert_equal "FANTASIA", snapshot.trade_name
  end

  test "rejects an invalid CNPJ" do
    error = assert_raises(ArgumentError) { Operations::RegisterManually.call(valid_attrs.merge("cnpj" => "123")) }
    assert_equal "CNPJ inválido", error.message
  end

  test "rejects an invalid EC" do
    error = assert_raises(ArgumentError) { Operations::RegisterManually.call(valid_attrs.merge("ec" => "12")) }
    assert_equal "EC inválido", error.message
  end

  test "rejects an EC that changes CNPJ" do
    Operations::RegisterManually.call(valid_attrs)
    error = assert_raises(ArgumentError) do
      Operations::RegisterManually.call(valid_attrs.merge("cnpj" => "99999978000195", "report_id" => "1479"))
    end
    assert_match(/mudou de CNPJ/, error.message)
  end

  test "rejects a REPORT_ID associated with another channel name" do
    Channel.create!(external_id: "1478", name: "OUTRO MASTER")

    error = assert_raises(ArgumentError) { Operations::RegisterManually.call(valid_attrs) }

    assert_equal "REPORT_ID 1478 associado a outro CANAL", error.message
  end

  test "rejects revenue days that do not reconcile with the declared total" do
    error = assert_raises(ArgumentError) do
      Operations::RegisterManually.call(
        valid_attrs.merge(
          "previous_period" => "2026-07-01",
          "current_period" => "2026-08-01",
          "current_month_total" => "100",
          "day_01" => "10"
        )
      )
    end
    assert_match(/dias não reconciliam/, error.message)
  end

  test "rejects nonconsecutive revenue competencies" do
    error = assert_raises(ArgumentError) do
      Operations::RegisterManually.call(
        valid_attrs.merge(
          "previous_period" => "2026-06-01", "current_period" => "2026-08-01",
          "current_month_total" => "10", "day_01" => "10"
        )
      )
    end
    assert_equal "Competências devem ser meses consecutivos", error.message
  end

  test "rejects faturamento EC that is not in the map row" do
    rows = {
      "Mapa de Clientes BIN" => [ { "_row_number" => 2, "REPORT_ID" => "1", "CANAL" => "A",
        "SUB-CANAL" => "S", "EC" => "12345678", "CNPJ" => "12345678000195", "STATUS DO CONTRATO" => "Active" } ],
      "Faturamento" => [ { "_row_number" => 2, "CANAL" => "A", "SUB-CANAL" => "S", "EC" => "99999999",
        "CNPJ" => "12345678000195", "STATUS DO CONTRATO" => "Active", "fat_total_m1" => 0,
        "FATURAMENTO TOTAL DESTE MÊS" => 0 } ],
      "Ativacao" => []
    }
    (1..31).each do |day|
      rows["Faturamento"].first[format("DIA %02d_M_1", day)] = 0
      rows["Faturamento"].first[format("DIA %02d", day)] = 0
    end

    error = assert_raises(ArgumentError) { BinImport::Validator.new(rows).validate_identity! }
    assert_match(/ECs de Faturamento ausentes no Mapa/, error.message)
  end

  private

  def valid_attrs
    {
      "report_id" => "1478", "channel_name" => "MASTER", "sub_channel_name" => "MIC TESTE",
      "ec" => "12345678", "cnpj" => "12345678000195", "contract_status" => "Active",
      "legal_name" => "RAZAO", "trade_name" => "FANTASIA",
      "street_address" => "RUA TESTE 10", "cnae_code" => "5611201", "city" => "GOIANIA", "state" => "GO"
    }
  end
end
