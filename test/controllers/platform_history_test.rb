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

  # Mês no horário de Brasília: a entrada das 22h do último dia do mês é desse mês, mesmo
  # já sendo o dia 1º em UTC.
  test "uso por mês: pessoas, entradas, exportações e arquivos, no mês de Brasília" do
    last_night = Time.zone.local(Date.current.year, Date.current.month, 1, 0, 30) - 2.hours
    Audit.record("session.start", user: @guest).update_column(:created_at, last_night)
    2.times { Audit.record("session.start", user: @admin) }
    Audit.record("session.start", user: @guest)
    Audit.record("report.export", user: @guest, channel: @channel, metadata: { tela: "index", formato: "csv" })
    sign_in_as(@platform)

    get platform_organization_path(default_organization)

    current = I18n.l(Date.current, format: "%m/%Y")
    previous = I18n.l(Date.current.prev_month, format: "%m/%Y")
    rows = css_select("table[aria-label='Uso por mês'] tbody tr").to_h do |row|
      cells = row.css("td").map { |cell| cell.text.strip }
      [ cells.first, cells.drop(1).map(&:to_i) ]
    end
    # Pessoas, entradas, exportações, arquivos: o arquivo é o da planilha sintética, de agora.
    assert_equal [ 2, 3, 1, 1 ], rows.fetch(current)
    assert_equal [ 1, 1, 0, 0 ], rows.fetch(previous), "as 22h do último dia ficam no mês de Brasília"
    assert_no_match LEAKS, response.body
  end

  test "segurança dos últimos 30 dias: recusas, bloqueios, códigos errados e acesso vencido" do
    Audit.record("session.failed", user: @guest, metadata: { email_tentado: @guest.email_address, bloqueada: false })
    Audit.record("session.failed", user: @guest, metadata: { email_tentado: @guest.email_address, bloqueada: true })
    Audit.record("mfa.failed", user: @guest)
    Audit.record("session.expired_access", user: @guest)
    Audit.record("user.mfa_reset", user: @platform, record: @guest)
    @guest.update_column(:locked_until, 10.minutes.from_now)
    sign_in_as(@platform)

    get platform_organization_path(default_organization)

    within_section = css_select("section[aria-label='Segurança']").first.text
    assert_match(/Entradas recusadas\s*2/, within_section)
    assert_match(/Bloqueios por tentativas\s*1/, within_section)
    assert_match(/Códigos de verificação errados\s*1/, within_section)
    assert_match(/Segundo fator reiniciado\s*1/, within_section)
    assert_match(/Tentativas com acesso vencido\s*1/, within_section)
    assert_match(/Contas bloqueadas agora\s*1/, within_section)
  end

  test "saúde da carteira: dias sem arquivo, falhas recentes e lotes parados" do
    ImportBatch.create!(organization: default_organization, source_filename: "f.xlsx", file_checksum: "falha-1", status: "failed")
    ImportBatch.create!(organization: default_organization, source_filename: "r.xlsx", file_checksum: "rev-1",
      status: "pending_review", channel: @channel)
    sign_in_as(@platform)

    get platform_organization_path(default_organization)

    within_section = css_select("section[aria-label='Saúde da carteira']").first.text
    assert_match(/Dias desde o último arquivo\s*0/, within_section)
    assert_match(/Falhas em 30 dias\s*1/, within_section)
    assert_match(/Em revisão agora\s*1/, within_section)
    assert_no_match LEAKS, response.body
  end

  # Quem apaga é a organização; quem restaura é a plataforma. Os dois lados aparecem pelo
  # REPORT_ID, sem o nome do Master.
  test "Masters apagados e restaurados aparecem pelo REPORT_ID, com quem fez" do
    Audit.record("channel.deleted", user: @admin, record: @channel, channel: @channel,
      metadata: { "master" => @channel.name, "report_id" => @channel.external_id })
    Audit.record("channel.restored", user: @platform, record: default_organization,
      metadata: { report_id: @channel.external_id })
    sign_in_as(@platform)

    get platform_organization_path(default_organization)

    rows = css_select("table[aria-label='Masters apagados e restaurados'] tbody tr").map(&:text)
    assert_equal 2, rows.size
    assert(rows.any? { |row| row.include?("Apagou Master") && row.include?(@channel.external_id) && row.include?("admin-a@exemplo.com") })
    assert(rows.any? { |row| row.include?("Restaurou Master") && row.include?(@channel.external_id) })
    assert_no_match LEAKS, response.body
  end

  test "gestão de acessos dos últimos 30 dias em números, sem dizer quais telas" do
    Audit.record("user.created", user: @admin, record: @guest, metadata: { alvo: @guest.email_address })
    Audit.record("user.access_changed", user: @admin, record: @guest,
      metadata: { permissoes_antes: [ "reports_revenue" ], permissoes_depois: [ "reports_clover" ] })
    Audit.record("user.access_validity_changed", user: @admin, record: @guest,
      metadata: { validade_antes: "indeterminado", validade_depois: "2026-12-31" })
    Audit.record("user.deactivated", user: @admin, record: @guest)
    sign_in_as(@platform)

    get platform_organization_path(default_organization)

    within_section = css_select("section[aria-label='Gestão de acessos']").first.text
    assert_match(/Convites\s*1/, within_section)
    assert_match(/Mudanças de permissão\s*1/, within_section)
    assert_match(/Mudanças de validade\s*1/, within_section)
    assert_match(/Desativações\s*1/, within_section)
    assert_match(/Contas alteradas\s*1/, within_section)
    assert_no_match(/Clover Capital/, within_section)
  end

  # A linha do tempo de uma conta: convite, primeiro acesso, segundo fator, validade,
  # permissões em números, desativação — o ciclo de vida, não a atividade na carteira.
  test "a linha do tempo da conta mostra o ciclo de vida, sem a atividade na carteira" do
    Audit.record("user.created", user: @admin, record: @guest, metadata: { alvo: @guest.email_address })
    Audit.record("session.start", user: @guest)
    Audit.record("mfa.enrolled", user: @guest)
    Audit.record("user.access_validity_changed", user: @admin, record: @guest,
      metadata: { validade_antes: "indeterminado", validade_depois: "2026-12-31" })
    Audit.record("report.export", user: @guest, channel: @channel, metadata: { tela: "index", formato: "csv" })
    Audit.record("note.saved", user: @guest, metadata: { caracteres: 10 })
    sign_in_as(@platform)

    get platform_user_path(@guest)

    assert_response :success
    assert_match "Convidou alguém", response.body
    assert_match "Cadastrou o segundo fator", response.body
    assert_match "validade depois: 2026-12-31", response.body
    assert_match "Primeiro acesso", response.body
    assert_no_match(/Exportou relatório|Salvou anotação/, response.body)
    assert_no_match LEAKS, response.body
  end

  test "a lista de convidados leva à linha do tempo, que não abre para quem não é da plataforma" do
    sign_in_as(@platform)
    get platform_organization_path(default_organization)
    assert_select "a[href=?]", platform_user_path(@guest)
    sign_out

    travel 31.seconds
    sign_in_as(@admin)
    get platform_user_path(@guest)
    assert_response :forbidden
  end

  test "a plataforma não abre a linha do tempo de outra conta da plataforma" do
    other = platform_admin_user(email: "plataforma-2@exemplo.com")
    sign_in_as(@platform)

    get platform_user_path(other)

    assert_response :forbidden
  end
end
