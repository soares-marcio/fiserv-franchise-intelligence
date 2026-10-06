require "test_helper"

# A trilha responde "quem fez o quê" — e só isso. O que ela **não** pode guardar é o
# conteúdo protegido: CNPJ, faturamento, texto de anotação. Uma trilha que repete o dado
# vira um segundo vazamento, e um que ninguém recorta por escopo.
class AuditTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @channel = Channel.create!(organization: default_organization, external_id: "9911", name: "MASTER DA TRILHA")
    @actor = scoped_user(permissions: [ *Permission::REPORT_KEYS, Permission::REPORTS_EXPORT,
      Permission::NOTES_READ, Permission::NOTES_WRITE ], channel: @channel, email: "ator@exemplo.com")
  end

  test "entrada, saída e tentativa recusada ficam registradas" do
    post session_path, params: { email_address: @actor.email_address, password: "errada-de-proposito" }

    failure = AuditEvent.find_by(action: "session.failed")
    assert_equal @actor, failure.user
    assert_equal @actor.email_address, failure.metadata["email_tentado"]

    sign_in_as(@actor)
    assert AuditEvent.exists?(action: "session.start", user: @actor)

    delete session_path
    assert AuditEvent.exists?(action: "session.end", user: @actor)
  end

  # E-mail que não existe também entra: é o que permite ver uma varredura acontecendo.
  test "tentativa em conta inexistente é registrada sem usuário" do
    post session_path, params: { email_address: "ninguem@exemplo.com", password: "qualquer-coisa-1" }

    event = AuditEvent.find_by(action: "session.failed")
    assert_nil event.user
    assert_equal "sistema", event.actor_email
    assert_equal "ninguem@exemplo.com", event.metadata["email_tentado"]
  end

  test "exportação registra a tela, o formato e o recorte — e não o conteúdo" do
    import_synthetic_workbook
    actor = scoped_user(permissions: [ *Permission::REPORT_KEYS, Permission::REPORTS_EXPORT ],
      channel: Channel.find_by!(name: BinWorkbook::CHANNEL), email: "exporta@exemplo.com")
    sign_in_as(actor)

    get recurring_reports_path(format: :csv)

    event = AuditEvent.find_by(action: "report.export")
    assert_equal actor, event.user
    assert_equal "recurring", event.metadata["tela"]
    assert_equal "csv", event.metadata["formato"]
    assert_no_match(/\d{14}/, event.metadata.to_json, "a trilha não repete CNPJ")
  end

  test "anotação registra que houve edição, não o que foi escrito" do
    import_synthetic_workbook
    company = Establishment.find_by!(ec: "30000001").company
    actor = scoped_user(permissions: [ Permission::ESTABLISHMENTS_READ, Permission::NOTES_READ, Permission::NOTES_WRITE ],
      channel: Channel.find_by!(name: BinWorkbook::CHANNEL), email: "anota@exemplo.com")
    sign_in_as(actor)

    patch company_note_path(company), params: { body: "<div>Cliente pediu desconto de 20%</div>" }

    event = AuditEvent.find_by(action: "note.saved")
    assert_equal actor, event.user
    assert_no_match(/desconto/, event.metadata.to_json, "o texto da anotação não entra na trilha")
    assert_no_match(/#{company.cnpj}/, event.metadata.to_json)
  end

  # Quem aprovou precisa poder responder depois pelo que saiu da carteira naquele dia.
  test "aprovação registra o resumo do que foi decidido" do
    first_item = import_synthetic_workbook
    batch = partial_batch(first_item.channel)
    revisor = admin_user(email: "revisor@exemplo.com")

    Operations::ReviewBatch.approve(batch: batch, reviewer: revisor, note: "Conferido")

    event = AuditEvent.find_by(action: "batch.approved")
    assert_equal revisor, event.user
    assert_equal batch.id, event.record_id
    assert_operator event.metadata["saindo"].to_i, :>, 0, "o resumo diz quantos ECs saíram"
  end

  test "recusa registra o motivo escrito por quem recusou" do
    first_item = import_synthetic_workbook
    batch = partial_batch(first_item.channel)
    revisor = admin_user(email: "recusador@exemplo.com")

    Operations::ReviewBatch.reject(batch: batch, reviewer: revisor, note: "Arquivo incompleto")

    event = AuditEvent.find_by(action: "batch.rejected")
    assert_equal "Arquivo incompleto", event.metadata["motivo"]
  end

  # A falha da trilha não pode derrubar a operação: perder o registro é ruim; perder o
  # trabalho do usuário é pior.
  test "erro ao registrar não interrompe a ação" do
    # Ação nula viola o NOT NULL da tabela: é o jeito de provocar a falha pelo caminho real,
    # sem substituir o comportamento do Active Record.
    assert_nothing_raised { Audit.record(nil, user: @actor) }
    assert_nil Audit.record(nil, user: @actor), "falha registra nada e devolve nada"
  end

  private

  def partial_batch(channel)
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-parcial.xlsx")
    BinWorkbook.write(path, stores: BinWorkbook.default_stores.first(1))
    ImportBatch.create!(organization: default_organization, source_filename: "parcial.xlsx", status: "pending",
      file_checksum: Digest::SHA256.file(path).hexdigest)
    BinImport::Importer.new(path, source_filename: "parcial.xlsx", organization: default_organization).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end

# A trilha é leitura de administração: quem opera o portal não precisa saber o que os
# outros fizeram.
class AuditEventsScreenTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  test "sem a chave de administração, a trilha responde 403" do
    sign_in_as(scoped_user(permissions: [ *Permission::REPORT_KEYS ], email: "comum@exemplo.com"))

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
