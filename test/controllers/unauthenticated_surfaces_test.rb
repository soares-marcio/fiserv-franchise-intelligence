require "test_helper"

# Os caminhos que **não** herdam do ApplicationController. Cada um deles já esteve aberto
# em algum projeto porque ninguém lembrou que existia: o Active Storage serve a planilha
# original da BIN, o Action Cable não passa por before_action nenhum, e o controller de
# anexos herda do engine.
class UnauthenticatedSurfacesTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @batch = ImportBatch.create!(organization: default_organization, source_filename: "planilha.xlsx", file_checksum: "abc123",
      status: "validated")
    @batch.source_file.attach(io: StringIO.new("conteúdo da planilha"),
      filename: "planilha.xlsx", content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  test "sem sessão, o download da planilha original é negado" do
    get rails_blob_path(@batch.source_file, disposition: "attachment")

    assert_redirected_to new_session_path, "a planilha traz CNPJ, telefone e endereço reais"
  end

  test "com sessão, o download acontece" do
    sign_in_as(admin_user)

    get rails_blob_path(@batch.source_file, disposition: "attachment")

    assert_response :redirect
    assert_no_match(/session/, response.location.to_s)
  end

  # A rota de upload direto responde JSON ao editor da anotação: redirecionar para o login
  # devolveria HTML no lugar do JSON que o Trix espera, e o erro apareceria como falha
  # silenciosa de upload.
  test "upload direto sem sessão é negado, e nenhum blob é criado" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post rails_direct_uploads_path, params: {
        blob: { filename: "a.png", byte_size: 10, checksum: "x", content_type: "image/png" }
      }
    end

    assert_response :redirect
  end
end

# Sessão válida não é autorização: o anexo de uma anotação pertence a um cliente, e o
# cliente pertence a uma carteira.
class BlobAuthorizationTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    import_synthetic_workbook
    @company = Establishment.find_by!(ec: "30000001").company
    @anexo = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("conteúdo"),
      filename: "recibo.pdf", content_type: "application/pdf")
    # Como a tela grava: o anexo vem embutido na marcação do corpo, e é o Action Text que
    # cria o vínculo ao salvar. Anexar pelo `embeds` não persiste nada.
    @nota = Operations::SaveCompanyNote.call(organization: default_organization, cnpj: @company.cnpj,
      body: %(<div>Com anexo</div><action-text-attachment sgid="#{@anexo.attachable_sgid}"></action-text-attachment>))
    @canal = Channel.find_by!(name: BinWorkbook::CANAL)
    @outro = Channel.create!(organization: default_organization, external_id: "7777", name: "MASTER DE FORA")
  end

  test "quem não alcança o cliente não baixa o anexo da anotação dele" do
    sign_in_as(scoped_user(permissions: [ Permission::NOTES_READ ], channel: @outro,
      email: "de-fora@exemplo.com"))

    get rails_blob_path(@anexo, disposition: "attachment")

    assert_response :not_found
  end

  test "quem alcança o cliente baixa normalmente" do
    sign_in_as(scoped_user(permissions: [ Permission::NOTES_READ ], channel: @canal,
      email: "de-dentro@exemplo.com"))

    get rails_blob_path(@anexo, disposition: "attachment")

    assert_response :redirect
    assert_no_match(/session/, response.location.to_s)
  end
end

# O WebSocket não passa por before_action nenhum: quem entra nele recebe os avisos de
# atualização da tela de importação.
class CableConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "conexão sem cookie de sessão é recusada" do
    assert_reject_connection { connect }
  end

  test "conexão com sessão válida identifica o usuário" do
    user = User.create!(organization: default_organization, email_address: "cabo@exemplo.com", name: "Cabo", password: Accounts::PASSWORD)
    session = user.sessions.create!(last_active_at: Time.current)

    cookies.signed[:session_id] = session.id
    connect

    assert_equal user, connection.current_user
  end
end
