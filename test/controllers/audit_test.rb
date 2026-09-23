require "test_helper"

# A trilha responde "quem fez o quê" — e só isso. O que ela **não** pode guardar é o
# conteúdo protegido: CNPJ, faturamento, texto de anotação. Uma trilha que repete o dado
# vira um segundo vazamento, e um que ninguém recorta por escopo.
class AuditTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @canal = Channel.create!(external_id: "9911", name: "MASTER DA TRILHA")
    @ator = scoped_user(permissions: [ Permission::REPORTS_READ, Permission::REPORTS_EXPORT,
      Permission::NOTES_READ, Permission::NOTES_WRITE ], channel: @canal, email: "ator@exemplo.com")
  end

  test "entrada, saída e tentativa recusada ficam registradas" do
    post session_path, params: { email_address: @ator.email_address, password: "errada-de-proposito" }

    falha = AuditEvent.find_by(action: "session.failed")
    assert_equal @ator, falha.user
    assert_equal @ator.email_address, falha.metadata["email_tentado"]

    sign_in_as(@ator)
    assert AuditEvent.exists?(action: "session.start", user: @ator)

    delete session_path
    assert AuditEvent.exists?(action: "session.end", user: @ator)
  end

  # E-mail que não existe também entra: é o que permite ver uma varredura acontecendo.
  test "tentativa em conta inexistente é registrada sem usuário" do
    post session_path, params: { email_address: "ninguem@exemplo.com", password: "qualquer-coisa-1" }

    evento = AuditEvent.find_by(action: "session.failed")
    assert_nil evento.user
    assert_equal "sistema", evento.actor_email
    assert_equal "ninguem@exemplo.com", evento.metadata["email_tentado"]
  end

  test "exportação registra a tela, o formato e o recorte — e não o conteúdo" do
    import_synthetic_workbook
    ator = scoped_user(permissions: [ Permission::REPORTS_READ, Permission::REPORTS_EXPORT ],
      channel: Channel.find_by!(name: BinWorkbook::CANAL), email: "exporta@exemplo.com")
    sign_in_as(ator)

    get recurring_reports_path(format: :csv)

    evento = AuditEvent.find_by(action: "report.export")
    assert_equal ator, evento.user
    assert_equal "recurring", evento.metadata["tela"]
    assert_equal "csv", evento.metadata["formato"]
    assert_no_match(/\d{14}/, evento.metadata.to_json, "a trilha não repete CNPJ")
  end

  test "anotação registra que houve edição, não o que foi escrito" do
    import_synthetic_workbook
    company = Establishment.find_by!(ec: "30000001").company
    ator = scoped_user(permissions: [ Permission::NOTES_READ, Permission::NOTES_WRITE ],
      channel: Channel.find_by!(name: BinWorkbook::CANAL), email: "anota@exemplo.com")
    sign_in_as(ator)

    patch company_note_path(company), params: { body: "<div>Cliente pediu desconto de 20%</div>" }

    evento = AuditEvent.find_by(action: "note.saved")
    assert_equal ator, evento.user
    assert_no_match(/desconto/, evento.metadata.to_json, "o texto da anotação não entra na trilha")
    assert_no_match(/#{company.cnpj}/, evento.metadata.to_json)
  end

  # Quem aprovou precisa poder responder depois pelo que saiu da carteira naquele dia.
  test "aprovação registra o resumo do que foi decidido" do
    primeiro = import_synthetic_workbook
    lote = lote_parcial(primeiro.channel)
    revisor = admin_user(email: "revisor@exemplo.com")

    Operations::ReviewBatch.approve(batch: lote, reviewer: revisor, note: "Conferido")

    evento = AuditEvent.find_by(action: "batch.approved")
    assert_equal revisor, evento.user
    assert_equal lote.id, evento.record_id
    assert_operator evento.metadata["saindo"].to_i, :>, 0, "o resumo diz quantos ECs saíram"
  end

  test "recusa registra o motivo escrito por quem recusou" do
    primeiro = import_synthetic_workbook
    lote = lote_parcial(primeiro.channel)
    revisor = admin_user(email: "recusador@exemplo.com")

    Operations::ReviewBatch.reject(batch: lote, reviewer: revisor, note: "Arquivo incompleto")

    evento = AuditEvent.find_by(action: "batch.rejected")
    assert_equal "Arquivo incompleto", evento.metadata["motivo"]
  end

  # A falha da trilha não pode derrubar a operação: perder o registro é ruim; perder o
  # trabalho do usuário é pior.
  test "erro ao registrar não interrompe a ação" do
    # Ação nula viola o NOT NULL da tabela: é o jeito de provocar a falha pelo caminho real,
    # sem substituir o comportamento do Active Record.
    assert_nothing_raised { Audit.record(nil, user: @ator) }
    assert_nil Audit.record(nil, user: @ator), "falha registra nada e devolve nada"
  end

  private

  def lote_parcial(canal)
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-parcial.xlsx")
    BinWorkbook.write(path, lojas: BinWorkbook.default_lojas.first(1))
    ImportBatch.create!(source_filename: "parcial.xlsx", status: "pending",
      file_checksum: Digest::SHA256.file(path).hexdigest)
    BinImport::Importer.new(path, source_filename: "parcial.xlsx").call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end

# A trilha é leitura de administração: quem opera o portal não precisa saber o que os
# outros fizeram.
class AuditEventsScreenTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  test "sem a chave de administração, a trilha responde 403" do
    sign_in_as(scoped_user(permissions: [ Permission::REPORTS_READ ], email: "comum@exemplo.com"))

    get audit_events_path

    assert_response :forbidden
  end

  test "com a chave, a trilha abre e lista os eventos" do
    sign_in_as(admin_user)
    Audit.record("session.start", user: User.last)

    get audit_events_path

    assert_response :success
    assert_select "table", 1
  end
end
