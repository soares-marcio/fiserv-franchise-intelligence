require "test_helper"

# Arquivo que cumpre o template mas chega sem CANAL: em vez de recusar o import, a carteira
# entra sob um canal fictício. O REPORT_ID continua sendo a identidade do canal — é ele que
# diz se a planilha é de uma carteira já conhecida.
class ChannelFallbackTest < ActiveSupport::TestCase
  test "planilha sem canal entra sob SEM CANAL, com o REPORT_ID do arquivo" do
    batch = import_synthetic_workbook(channel: nil)

    assert_equal BinImport::ChannelResolver::FALLBACK_NAME, batch.channel.name
    assert_equal BinWorkbook::REPORT_ID, batch.channel.external_id
    assert_equal "validated", batch.status
  end

  # O canal é identificado pelo REPORT_ID: uma planilha sem CANAL de uma carteira já
  # importada não pode renomear o canal para "SEM CANAL".
  test "sem canal, um REPORT_ID já conhecido mantém o nome que tinha" do
    first_item = import_synthetic_workbook

    stores = BinWorkbook.default_stores
    stores.first.current_days = stores.first.current_days.merge(1 => 999)
    second = import_synthetic_workbook(stores:, filename: "BIN_TESTE_20260812.xlsx", channel: nil)

    assert_equal first_item.channel_id, second.channel_id
    assert_equal BinWorkbook::CHANNEL, second.channel.name
  end

  # A ausência de canal não é normalidade: cada linha do Mapa sem CANAL vira anomalia, para
  # o analista saber que a carteira entrou sob o nome fictício.
  test "as linhas sem canal ficam registradas como anomalia" do
    batch = import_synthetic_workbook(channel: nil)

    anomaly = DataAnomaly.find_by(anomaly_type: "row_without_canal")
    assert anomaly, "import sem canal precisa registrar a anomalia"
    assert_equal batch.id, anomaly.last_import_batch_id
  end
end
