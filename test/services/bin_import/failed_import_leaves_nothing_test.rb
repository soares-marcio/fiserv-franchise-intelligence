require "test_helper"

# Arquivo que falha não deixa nada gravado além do próprio lote falho, com o motivo. Em
# 01/10/2026 uma planilha com EC duplicado criou o Master "MASTER RAMOS E SILVA" sem dado
# nenhum: o Master nascia antes da validação, e descartar o lote não o levava junto.
class FailedImportLeavesNothingTest < ActiveSupport::TestCase
  test "planilha de Master novo que falha na validação não cria o Master" do
    stores = BinWorkbook.default_stores
    duplicated = stores + [ stores.first ]

    before = counts
    error = assert_raises(ArgumentError) do
      import_synthetic_workbook(stores: duplicated, report_id: "9999", channel: "MASTER NOVO")
    end

    assert_equal before, counts, "a planilha que falhou deixou dado gravado"

    assert_match(/aparece 2 vezes/, error.message)
    batch = ImportBatch.order(:id).last
    assert_equal "failed", batch.status
    assert_nil batch.channel_id, "o lote falho não aponta para Master nenhum"
    assert batch.discardable?
  end

  test "depois da falha, o arquivo corrigido cria o Master normalmente" do
    stores = BinWorkbook.default_stores
    assert_raises(ArgumentError) do
      import_synthetic_workbook(stores: stores + [ stores.first ], report_id: "9999", channel: "MASTER NOVO")
    end

    batch = import_synthetic_workbook(stores:, report_id: "9999", channel: "MASTER NOVO",
      filename: "BIN_TESTE_20260812.xlsx")

    assert_equal "validated", batch.status
    assert_equal "MASTER NOVO", batch.channel.name
    assert_equal 1, Channel.where(external_id: "9999").count
  end

  test "falha num Master que já existe não mexe nele" do
    import_synthetic_workbook
    channel = Channel.find_by!(external_id: BinWorkbook::REPORT_ID)
    stores = BinWorkbook.default_stores

    before = counts
    assert_raises(ArgumentError) do
      import_synthetic_workbook(stores: stores + [ stores.first ], filename: "BIN_TESTE_20260813.xlsx")
    end

    assert_equal before, counts

    assert_equal channel.id, ImportBatch.order(:id).last.channel_id
  end

  private

  def counts
    [ Channel, SubChannel, Establishment, Company, MapSnapshot, RevenueSnapshot, DailyRevenue, DataAnomaly ]
      .to_h { |model| [ model.name, model.count ] }
  end
end
