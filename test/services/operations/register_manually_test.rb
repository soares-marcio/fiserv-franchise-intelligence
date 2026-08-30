require "test_helper"

class Operations::RegisterManuallyTest < ActiveSupport::TestCase
  test "creates a client with the same identity rules as import" do
    batch = Operations::RegisterManually.call(valid_attrs)

    assert_equal "validated", batch.status
    establishment = Establishment.find_by(ec: "12345678")
    snapshot = establishment.current_map_snapshot
    assert_equal "12345678000195", establishment.company.cnpj
    assert_equal "MASTER", establishment.channel.canal
    assert_equal "RUA TESTE 10", snapshot.endereco
    assert_equal "5611201", snapshot.cnae_codigo
    assert_equal "MIC TESTE", snapshot.sub_channel.sub_canal
  end

  test "grava razão social e nome fantasia sem inverter" do
    Operations::RegisterManually.call(valid_attrs)
    snapshot = Establishment.find_by!(ec: "12345678").current_map_snapshot

    assert_equal "RAZAO", snapshot.razao_social
    assert_equal "FANTASIA", snapshot.nome_fantasia
  end

  test "propaga os nomes para o snapshot de faturamento" do
    Operations::RegisterManually.call(valid_attrs.merge(
      "competencia_m1" => "2026-07-01", "competencia_atual" => "2026-08-01",
      "fat_total_mes_atual" => "100", "dia_01" => "100"
    ))
    snapshot = RevenueSnapshot.joins(:establishment).find_by!(establishments: { ec: "12345678" })

    assert_equal "RAZAO", snapshot.razao_social
    assert_equal "FANTASIA", snapshot.nome_fantasia
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
    Channel.create!(external_id: "1478", canal: "OUTRO MASTER")

    error = assert_raises(ArgumentError) { Operations::RegisterManually.call(valid_attrs) }

    assert_equal "REPORT_ID 1478 associado a outro CANAL", error.message
  end

  test "rejects revenue days that do not reconcile with the declared total" do
    error = assert_raises(ArgumentError) do
      Operations::RegisterManually.call(
        valid_attrs.merge(
          "competencia_m1" => "2026-07-01",
          "competencia_atual" => "2026-08-01",
          "fat_total_mes_atual" => "100",
          "dia_01" => "10"
        )
      )
    end
    assert_match(/dias não reconciliam/, error.message)
  end

  test "rejects nonconsecutive revenue competencies" do
    error = assert_raises(ArgumentError) do
      Operations::RegisterManually.call(
        valid_attrs.merge(
          "competencia_m1" => "2026-06-01", "competencia_atual" => "2026-08-01",
          "fat_total_mes_atual" => "10", "dia_01" => "10"
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
      "report_id" => "1478", "canal" => "MASTER", "sub_canal" => "MIC TESTE",
      "ec" => "12345678", "cnpj" => "12345678000195", "status_contrato" => "Active",
      "razao_social" => "RAZAO", "nome_fantasia" => "FANTASIA",
      "endereco" => "RUA TESTE 10", "cnae_codigo" => "5611201", "cidade" => "GOIANIA", "estado" => "GO"
    }
  end
end
