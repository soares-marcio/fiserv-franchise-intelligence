require "test_helper"

class BinImport::AnomalyDetectorTest < ActiveSupport::TestCase
  test "aponta o EC 3xx que tem um 9xx irmão no mesmo CNPJ" do
    batch = import_synthetic_workbook
    anomalia = DataAnomaly.find_by(anomaly_type: "ec_duplicate_candidate")

    assert_equal batch.channel_id, anomalia.channel_id
    assert_equal "atencao", anomalia.severity
    assert_equal "30000001", anomalia.establishment.ec
    assert_equal "90000001", anomalia.details["paired_ec"]
  end

  test "não aponta duplicata quando o 9xx é de outro CNPJ" do
    lojas = BinWorkbook.default_lojas
    lojas[1].cnpj = "77888999000155"
    import_synthetic_workbook(lojas:)

    assert_empty DataAnomaly.where(anomaly_type: "ec_duplicate_candidate")
  end

  test "aponta CNPJ presente em mais de um subcanal" do
    lojas = BinWorkbook.default_lojas
    lojas[1].name = "MIC GAMA"
    import_synthetic_workbook(lojas:)

    anomalia = DataAnomaly.find_by(anomaly_type: "company_in_multiple_sub_channels")
    assert_equal "11222333000181", anomalia.company.cnpj
    assert_equal [ "MIC ALFA", "MIC GAMA" ], anomalia.details["sub_channels"]
  end

  test "aponta EC que trocou de subcanal entre lotes" do
    import_synthetic_workbook
    mudadas = BinWorkbook.default_lojas
    mudadas.first.name = "MIC DELTA"
    import_synthetic_workbook(lojas: mudadas, filename: "BIN_TESTE_20260812.xlsx")

    anomalia = DataAnomaly.find_by(anomaly_type: "ec_changed_sub_channel")
    assert_equal "30000001", anomalia.establishment.ec
    assert_equal "MIC ALFA", anomalia.details["previous"]
    assert_equal "MIC DELTA", anomalia.details["current"]
  end

  test "aponta linha do Mapa sem CANAL preenchido" do
    batch = import_synthetic_workbook
    RawImportRow.create!(
      import_batch: batch, sheet_name: "Mapa de Clientes BIN", row_number: 99,
      payload: { "EC" => "30000009", "CANAL" => "" }
    )

    BinImport::AnomalyDetector.new(batch).call
    anomalia = DataAnomaly.find_by(anomaly_type: "row_without_canal")

    assert_equal 99, anomalia.details["row_number"]
    assert_equal "Mapa de Clientes BIN", anomalia.details["sheet"]
  end

  test "registra corte observado abaixo do que a data do arquivo sugere" do
    # Corte observado é dia 10; arquivo de 15/08 sugere cobertura até o dia 14.
    batch = import_synthetic_workbook(filename: "BIN_TESTE_20260815.xlsx")
    anomalia = DataAnomaly.find_by(anomaly_type: "cutoff_below_file_date")

    assert anomalia, "divergência entre corte observado e data do arquivo deve virar anomalia"
    assert_equal batch.current_month_cutoff_day, anomalia.details["corte_observado"]
    assert_equal 14, anomalia.details["corte_esperado"]
    assert_equal "info", anomalia.severity
  end

  test "não registra divergência quando a data do arquivo bate com o corte" do
    import_synthetic_workbook(filename: "BIN_TESTE_20260811.xlsx")

    assert_empty DataAnomaly.where(anomaly_type: "cutoff_below_file_date")
  end
end
