require "test_helper"

# Arquivo que cumpre o template mas chega sem CANAL: em vez de recusar o import, a carteira
# entra sob um canal fictício. O REPORT_ID continua sendo a identidade do canal — é ele que
# diz se a planilha é de uma carteira já conhecida.
class ChannelFallbackTest < ActiveSupport::TestCase
  test "planilha sem canal entra sob SEM CANAL, com o REPORT_ID do arquivo" do
    batch = import_synthetic_workbook(canal: nil)

    assert_equal BinImport::ChannelResolver::FALLBACK_NAME, batch.channel.name
    assert_equal BinWorkbook::REPORT_ID, batch.channel.external_id
    assert_equal "validated", batch.status
  end

  # O canal é identificado pelo REPORT_ID: uma planilha sem CANAL de uma carteira já
  # importada não pode renomear o canal para "SEM CANAL".
  test "sem canal, um REPORT_ID já conhecido mantém o nome que tinha" do
    primeiro = import_synthetic_workbook

    lojas = BinWorkbook.default_lojas
    lojas.first.dias_atual = lojas.first.dias_atual.merge(1 => 999)
    segundo = import_synthetic_workbook(lojas:, filename: "BIN_TESTE_20260812.xlsx", canal: nil)

    assert_equal primeiro.channel_id, segundo.channel_id
    assert_equal BinWorkbook::CANAL, segundo.channel.name
  end

  # A ausência de canal não é normalidade: cada linha do Mapa sem CANAL vira anomalia, para
  # o analista saber que a carteira entrou sob o nome fictício.
  test "as linhas sem canal ficam registradas como anomalia" do
    batch = import_synthetic_workbook(canal: nil)

    anomalia = DataAnomaly.find_by(anomaly_type: "row_without_canal")
    assert anomalia, "import sem canal precisa registrar a anomalia"
    assert_equal batch.id, anomalia.last_import_batch_id
  end
end
