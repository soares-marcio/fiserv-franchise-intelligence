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
    lojas[1].sub_channel_name = "MIC GAMA"
    import_synthetic_workbook(lojas:)

    anomalia = DataAnomaly.find_by(anomaly_type: "company_in_multiple_sub_channels")
    assert_equal "11222333000181", anomalia.company.cnpj
    assert_equal [ "MIC ALFA", "MIC GAMA" ], anomalia.details["sub_channels"]
  end

  # O detector roda dentro da transação do import: uma consulta por empresa divergente
  # segurava a transação por mais tempo quanto pior fosse a planilha.
  test "lista os subcanais das empresas divergentes sem uma consulta por empresa" do
    lojas = (1..3).flat_map do |i|
      [ "MIC ALFA", "MIC GAMA" ].each_with_index.map do |sub_channel_name, j|
        BinWorkbook::Loja.new(
          ec: "30#{i}0000#{j}", cnpj: "5555#{i}666000017",
          sub_channel_name:, legal_name: "EMPRESA #{i} LTDA", trade_name: "LOJA #{i}#{j}",
          contract_status: "Active", dias_m1: { 1 => 100 }, dias_atual: { 1 => 50 },
          melhor_conversa: nil, proposta: false
        )
      end
    end
    batch = import_synthetic_workbook(lojas:)
    assert_equal 3, DataAnomaly.where(anomaly_type: "company_in_multiple_sub_channels").count

    counter = QueryCounter.new
    counter.while { ApplicationRecord.uncached { BinImport::AnomalyDetector.new(batch).call } }

    assert_equal 1, counter.matching(/COUNT\(DISTINCT sub_channel_id\)/).size
    assert_empty counter.matching(/FROM "companies" WHERE "companies"\."id" = /)
    assert_equal 1, counter.matching(/INNER JOIN "sub_channels".*"company_id" IN/).size
  end

  class QueryCounter
    def initialize = @statements = []

    def while(&block)
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        @statements << payload[:sql] unless payload[:cached]
      end
      block.call
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def matching(pattern) = @statements.grep(pattern)
  end

  test "aponta EC que trocou de subcanal entre lotes" do
    import_synthetic_workbook
    mudadas = BinWorkbook.default_lojas
    mudadas.first.sub_channel_name = "MIC DELTA"
    import_synthetic_workbook(lojas: mudadas, filename: "BIN_TESTE_20260812.xlsx")

    anomalia = DataAnomaly.find_by(anomaly_type: "ec_changed_sub_channel")
    assert_equal "30000001", anomalia.establishment.ec
    assert_equal "MIC ALFA", anomalia.details["previous"]
    assert_equal "MIC DELTA", anomalia.details["current"]
  end

  # "Anterior" é o snapshot imediatamente anterior, não o primeiro da história: um EC que
  # foi e voltou continua sendo apontado a cada mudança.
  test "compara com o snapshot imediatamente anterior, não com o primeiro da história" do
    import_synthetic_workbook
    mudadas = BinWorkbook.default_lojas
    mudadas.first.sub_channel_name = "MIC DELTA"
    import_synthetic_workbook(lojas: mudadas, filename: "BIN_TESTE_20260812.xlsx")
    # Volta para ALFA com outro faturamento: planilha idêntica à primeira seria recusada
    # pelo checksum.
    voltou = BinWorkbook.default_lojas
    voltou.first.dias_atual = voltou.first.dias_atual.merge(1 => 999)
    import_synthetic_workbook(lojas: voltou, filename: "BIN_TESTE_20260819.xlsx")

    anomalia = DataAnomaly.where(anomaly_type: "ec_changed_sub_channel").sole
    assert_equal 2, anomalia.occurrences
    assert_equal "MIC DELTA", anomalia.details["previous"]
    assert_equal "MIC ALFA", anomalia.details["current"]
  end

  # A história do Mapa cresce um snapshot por EC a cada planilha semanal; carregar todos
  # os anteriores como registros, com endereço e tudo, para ficar com um por EC é trabalho
  # que o banco faz sozinho.
  test "escolhe o snapshot anterior no banco, sem carregar a história inteira" do
    import_synthetic_workbook
    batch = import_synthetic_workbook(filename: "BIN_TESTE_20260812.xlsx")

    counter = QueryCounter.new
    counter.while { ApplicationRecord.uncached { BinImport::AnomalyDetector.new(batch).call } }

    assert_empty counter.matching(/SELECT "map_snapshots"\.\* FROM "map_snapshots" WHERE "map_snapshots"\."establishment_id" IN/)
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
    assert_equal batch.current_month_cutoff_day, anomalia.details["observed_cutoff"]
    assert_equal 14, anomalia.details["expected_cutoff"]
    assert_equal "info", anomalia.severity
  end

  test "não registra divergência quando a data do arquivo bate com o corte" do
    import_synthetic_workbook(filename: "BIN_TESTE_20260811.xlsx")

    assert_empty DataAnomaly.where(anomaly_type: "cutoff_below_file_date")
  end
end
