require "test_helper"

# O que a plataforma acompanha de cada organização: uso, segurança, saúde da carteira,
# Masters apagados, gestão de acessos e a linha do tempo de cada conta — sempre em contas,
# datas e contagens. Nome de Master ou de MIC, nome de arquivo, motivo escrito à mão e o
# recorte de uma exportação nunca chegam à plataforma (pedido de 07/10/2026).
class PlatformHistoryTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  LEAKS = /#{Regexp.escape(BinWorkbook::CHANNEL)}|MIC ALFA|30000001|planilha-secreta|motivo-secreto/

  setup do
    import_synthetic_workbook
    @channel = Channel.find_by!(name: BinWorkbook::CHANNEL)
    @platform = platform_admin_user
    @admin = admin_user(email: "admin-a@exemplo.com")
    @guest = scoped_user(permissions: [ Permission::REPORTS_REVENUE ], channel: @channel,
      email: "convidado@exemplo.com", created_by: @admin)
  end

  # O "Apagou Master" leva o nome do Master nos metadados, para a organização ler a própria
  # trilha; a plataforma lia o mesmo evento sem filtro. Lista fechada de chaves, e não lista
  # de exclusão: chave nova não vaza por esquecimento.
  test "o histórico da organização não mostra à plataforma nome de Master, de MIC, de arquivo nem motivo" do
    Audit.record("channel.deleted", user: @admin, record: @channel, channel: @channel,
      metadata: { "master" => @channel.name, "report_id" => @channel.external_id, "ecs" => 3 })
    Audit.record("sub_channel.deleted", user: @admin, channel: @channel, metadata: { "mic" => "MIC ALFA", "ecs" => 2 })
    Audit.record("batch.uploaded", user: @admin, channel: @channel, metadata: { arquivo: "planilha-secreta.xlsx" })
    Audit.record("batch.rejected", user: @admin, channel: @channel, metadata: { motivo: "motivo-secreto" })
    Audit.record("report.export", user: @guest, channel: @channel,
      metadata: { tela: "index", formato: "csv", escopo: "org:1|c:#{@channel.id}" })
    sign_in_as(@platform)

    get history_platform_organization_path(default_organization)

    assert_response :success
    assert_match "Apagou Master", response.body
    assert_match "REPORT_ID: #{@channel.external_id}", response.body
    assert_match "formato: csv", response.body
    assert_no_match LEAKS, response.body
    assert_no_match(/escopo/, response.body)
  end
end
