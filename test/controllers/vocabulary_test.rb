require "test_helper"

# Master e MIC são o vocabulário do negócio — é o que os próprios dados dizem: o canal chama-se
# "MASTER FRANQUEADO ..." e todo subcanal começa com "MIC". A tela é o **único** lugar onde esse
# vocabulário aparece: o banco e o código continuam em channel/sub_channel, e as mensagens do
# import continuam citando CANAL, porque apontam uma coluna que se chama assim na planilha.
#
# Sem este guarda a palavra antiga volta na próxima tela nova, e a interface passa a falar duas
# línguas para a mesma coisa.
class VocabularyTest < ActionDispatch::IntegrationTest
  # can(al|ais): "canais?" casaria "canai" com "s" opcional, e nunca a palavra do singular.
  VOCABULARIO_ANTIGO = /sub-?can(al|ais)/i

  setup do
    import_synthetic_workbook
    refresh_audit_views
    @sub_channel = SubChannel.find_by!(name: "MIC ALFA")
  end

  def paths
    [
      reports_path, stalled_reports_path, weekly_reports_path, recurring_reports_path,
      three_months_reports_path, establishments_path, import_batches_path, metabase_path,
      sub_channel_report_path(@sub_channel), search_path(q: "mic")
    ]
  end

  test "nenhuma tela escreve subcanal" do
    paths.each do |path|
      get path

      assert_response :success, path
      assert_no_match VOCABULARIO_ANTIGO, response.body, "#{path} ainda escreve subcanal"
    end
  end

  test "o filtro da carteira diz Master nas três telas que o oferecem" do
    [ reports_path, recurring_reports_path, three_months_reports_path ].each do |path|
      get path

      assert_select "span.section-label", { text: "Master da carteira" }, path
      assert_no_match(/Canal da carteira|Todos os canais/, response.body, path)
    end
  end

  # O canal fictício nasce com o nome da coluna que faltou — no banco ele continua "SEM CANAL",
  # que é o que o analista procura no arquivo; na tela, o vocabulário é o outro.
  test "o canal fictício aparece com o vocabulário da tela, sem mudar o dado" do
    channel = Channel.create!(external_id: "8888", name: BinImport::ChannelResolver::FALLBACK_NAME)

    assert_equal "SEM MASTER", ApplicationController.helpers.channel_name(channel)
    assert_equal "SEM CANAL", channel.reload.name
  end
end
