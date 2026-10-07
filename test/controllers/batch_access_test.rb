require "test_helper"

# Quem vê e quem mexe em cada lote. A planilha original é a carteira inteira de um Master
# num arquivo só — por isso a visibilidade aqui é nominal, e não "todos os lotes do meu
# Master": o autorizador libera arquivo a arquivo.
class BatchAccessTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @channel = Channel.create!(organization: default_organization, external_id: "4444", name: "MASTER DOS LOTES")
    @owner = scoped_user(permissions: all_batch_keys, channel: @channel, email: "dono@exemplo.com")
    @colleague = scoped_user(permissions: all_batch_keys, channel: @channel, email: "colega@exemplo.com")

    @mine = ImportBatch.create!(source_filename: "meu.xlsx", file_checksum: "meu-1",
      status: "failed", channel: @channel, uploaded_by: @owner)
    @colleagues_batch = ImportBatch.create!(source_filename: "dele.xlsx", file_checksum: "dele-1",
      status: "failed", channel: @channel, uploaded_by: @colleague)
  end

  test "a listagem mostra só os próprios envios" do
    sign_in_as(@owner)

    get import_batches_path

    assert_response :success
    assert_match(/meu\.xlsx/, response.body)
    assert_no_match(/dele\.xlsx/, response.body)
  end

  # 404, e não 403: dizer "existe, mas não é seu" já conta que aquele arquivo foi enviado.
  test "lote de outro ator responde 404" do
    sign_in_as(@owner)

    get import_batch_path(@colleagues_batch)

    assert_response :not_found
  end

  test "lote liberado nominalmente passa a aparecer e a abrir" do
    BatchGrant.create!(user: @owner, import_batch: @colleagues_batch, created_by: @colleague)
    sign_in_as(@owner)

    get import_batches_path
    assert_match(/dele\.xlsx/, response.body)

    get import_batch_path(@colleagues_batch)
    assert_response :success
  end

  # Ver não é mexer: mesmo com o lote liberado e com as chaves, reprocessar e descartar
  # continuam sendo só de quem enviou — descartar é irreversível e reprocessar reescreve a
  # consolidação do Master.
  test "lote liberado não pode ser reprocessado, ajustado nem descartado" do
    BatchGrant.create!(user: @owner, import_batch: @colleagues_batch, created_by: @colleague)
    sign_in_as(@owner)

    post reprocess_import_batch_path(@colleagues_batch)
    assert_response :forbidden

    patch update_cutoff_import_batch_path(@colleagues_batch), params: { max_known_day: 10 }
    assert_response :forbidden

    assert_no_difference -> { ImportBatch.count } do
      delete import_batch_path(@colleagues_batch)
    end
    assert_response :forbidden
  end

  test "no próprio lote, as ações funcionam" do
    sign_in_as(@owner)

    assert_difference -> { ImportBatch.count }, -1 do
      delete import_batch_path(@mine)
    end
  end

  # A planilha original vale o mesmo que o lote: quem não alcança o lote não baixa o arquivo.
  test "a planilha enviada segue a regra do lote" do
    @colleagues_batch.source_file.attach(io: StringIO.new("planilha"), filename: "dele.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    sign_in_as(@owner)

    get rails_blob_path(@colleagues_batch.source_file, disposition: "attachment")
    assert_response :not_found

    BatchGrant.create!(user: @owner, import_batch: @colleagues_batch, created_by: @colleague)
    get rails_blob_path(@colleagues_batch.source_file, disposition: "attachment")
    assert_response :redirect
  end

  # A revisão mostra o diff do Master inteiro. Um aprovador com um MIC só veria os outros —
  # por isso o lote em revisão nem entra no alcance dele (homologação de 29/09/2026).
  test "aprovador com um MIC só não alcança a revisão; com o Master inteiro, alcança" do
    mic = SubChannel.create!(channel: @channel, name: "MIC UM")
    pending = ImportBatch.create!(source_filename: "pendente.xlsx", file_checksum: "pend-1",
      status: "pending_review", channel: @channel, uploaded_by: @colleague)
    approve = [ Permission::BATCHES_READ, Permission::BATCHES_APPROVE ]

    do_mic = scoped_user(permissions: approve, sub_channel: mic, email: "mic@exemplo.com")
    sign_in_as(do_mic)
    get import_batches_path
    assert_no_match(/pendente\.xlsx/, response.body)
    get review_import_batch_path(pending)
    assert_response :not_found
    sign_out

    whole = scoped_user(permissions: approve, channel: @channel, email: "inteiro@exemplo.com")
    sign_in_as(whole)
    get import_batches_path
    assert_match(/pendente\.xlsx/, response.body)
    assert ImportBatchPolicy.new(whole, pending).review?
  end

  # Liberar é administrar acesso: exige a chave de convidar, alcançar o lote e o Master
  # inteiro — de quem libera e de quem recebe.
  test "liberar um arquivo: só a quem tem o Master inteiro, e revogar tira na hora" do
    mic = SubChannel.create!(channel: @channel, name: "MIC UM")
    approver = scoped_user(permissions: all_batch_keys + [ Permission::USERS_INVITE ],
      channel: @channel, email: "autorizador@exemplo.com")
    batch = ImportBatch.create!(source_filename: "liberavel.xlsx", file_checksum: "lib-1",
      status: "validated", channel: @channel, uploaded_by: approver)
    do_mic = scoped_user(permissions: [ Permission::BATCHES_READ ], sub_channel: mic, email: "mic@exemplo.com")
    sign_in_as(approver)

    get import_batch_path(batch)
    assert_match(/Quem vê este arquivo/, response.body)
    assert_match(/colega@exemplo\.com/, response.body, "quem tem o Master inteiro é oferecido")
    assert_no_match(/mic@exemplo\.com/, response.body, "quem tem um MIC não é oferecido")

    assert_difference -> { BatchGrant.count } do
      post import_batch_batch_grants_path(batch), params: { user_id: @colleague.to_param }
    end
    assert_no_difference -> { BatchGrant.count } do
      post import_batch_batch_grants_path(batch), params: { user_id: do_mic.to_param }
    end
    assert_match(/Master .* inteiro/, flash[:alert])
    sign_out

    sign_in_as(@colleague)
    get import_batches_path
    assert_match(/liberavel\.xlsx/, response.body)
    sign_out

    # Reentrar com quem já entrou exige outra janela do TOTP: o código não vale duas vezes.
    travel 31.seconds
    sign_in_as(approver)
    assert_difference -> { BatchGrant.count }, -1 do
      delete import_batch_batch_grant_path(batch, BatchGrant.find_by!(user: @colleague, import_batch: batch))
    end
    sign_out

    travel 31.seconds
    sign_in_as(@colleague)
    get import_batch_path(batch)
    assert_response :not_found
  end

  test "sem a chave de convidar, a seção de liberação não aparece e o POST é recusado" do
    sign_in_as(@owner)

    get import_batch_path(@mine)
    assert_no_match(/Quem vê este arquivo/, response.body)

    post import_batch_batch_grants_path(@mine), params: { user_id: @colleague.to_param }
    assert_response :forbidden
  end

  test "super admin enxerga e opera qualquer lote" do
    sign_in_as(admin_user)

    get import_batches_path
    assert_match(/dele\.xlsx/, response.body)

    get import_batch_path(@colleagues_batch)
    assert_response :success
  end

  # Quem só envia precisa da tela para enviar e para acompanhar o próprio lote; a planilha
  # original, que é a carteira inteira, continua atrás de "Ver lotes".
  test "só 'Enviar planilha' abre a tela de importação com os próprios envios, sem baixar a planilha" do
    sender = scoped_user(permissions: [ Permission::BATCHES_UPLOAD ], channel: @channel, email: "envia@exemplo.com")
    own = ImportBatch.create!(source_filename: "enviado.xlsx", file_checksum: "envia-1",
      status: "failed", channel: @channel, uploaded_by: sender)
    sign_in_as(sender)

    # O menu é lido numa tela que a pessoa tem: o 403 usa o cartão das páginas de erro, sem menu.
    get import_batches_path
    assert_response :success
    assert_select "nav.primary-nav a[href=?]", import_batches_path, text: /Importar arquivo/
    assert_match(/enviado\.xlsx/, response.body)
    assert_no_match(/meu\.xlsx|dele\.xlsx/, response.body)

    get import_batch_path(own)
    assert_response :success

    # O download passa pelo Active Storage e responde 404 pela mesma policy.
    assert_not ImportBatchPolicy.new(sender, own).download_source_file?
    assert ImportBatchPolicy.new(@owner, @mine).download_source_file?
  end

  private

  def all_batch_keys
    [ Permission::BATCHES_READ, Permission::BATCHES_UPLOAD, Permission::BATCHES_ADJUST,
      Permission::BATCHES_DISCARD ]
  end
end

# O Master do arquivo só se conhece depois do parse: a checagem de escopo acontece ali,
# antes de gravar qualquer linha.
class BatchUploadScopeTest < ActiveSupport::TestCase
  test "planilha de Master fora do escopo é recusada com mensagem clara" do
    another = Channel.create!(organization: default_organization, external_id: "3333", name: "MASTER ALHEIO")
    author = User.create!(organization: default_organization, email_address: "limitado@exemplo.com", name: "Limitado",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])
    author.access_grants.create!(channel: another)

    error = assert_raises(ArgumentError) do
      import_synthetic_workbook_as(author)
    end

    assert_match(/administrador da organização/, error.message,
      "Master novo: um colaborador não o inaugura, mesmo com concessão em outro Master")
    assert_equal 0, MapSnapshot.count, "nada pode ser gravado antes da checagem"
  end

  # A planilha substitui a carteira inteira do Master: um MIC dele não basta para enviá-la.
  # O canal é criado antes com a identidade da planilha sintética, para o MIC existir e o
  # resolvedor reaproveitá-lo.
  test "com um MIC só do Master, o envio é recusado antes de gravar qualquer linha" do
    channel = Channel.create!(organization: default_organization, external_id: BinWorkbook::REPORT_ID, name: BinWorkbook::CHANNEL)
    mic = SubChannel.create!(channel: channel, name: "MIC ALFA")
    author = User.create!(organization: default_organization, email_address: "parcial@exemplo.com", name: "Parcial",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])
    author.access_grants.create!(channel: channel, sub_channel: mic)

    error = nil
    assert_no_difference -> { MapSnapshot.count } do
      error = assert_raises(ArgumentError) { import_synthetic_workbook_as(author) }
    end

    assert_match(/inteiro/, error.message)
  end

  test "com o Master no escopo, a importação segue normalmente" do
    author = User.create!(organization: default_organization, email_address: "autorizado@exemplo.com", name: "Autorizado",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])

    # O canal nasce no próprio import; a concessão é dada depois, e o segundo envio passa.
    batch = import_synthetic_workbook
    author.access_grants.create!(channel: batch.channel)

    assert_nothing_raised { import_synthetic_workbook_as(author, filename: "BIN_TESTE_20260812.xlsx") }
  end

  private

  # O lote precisa nascer com o checksum do próprio arquivo: é por ele que o importador
  # reencontra o registro e descobre quem enviou. Com outro valor, ele criaria um lote novo
  # sem autor — e a checagem de escopo não teria a quem se aplicar.
  #
  # As lojas levam um dia a mais de faturamento: a planilha sintética só varia pelo
  # instante de criação, em segundos, e o segundo envio no mesmo segundo do primeiro
  # repetiria o checksum — o que na CI acontecia.
  def import_synthetic_workbook_as(author, filename: "BIN_TESTE_20260811.xlsx")
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
    stores = BinWorkbook.default_stores.map do |store|
      store.class.new(**store.to_h.merge(current_days: store.current_days.merge(20 => 77)))
    end
    BinWorkbook.write(path, stores:)
    ImportBatch.create!(source_filename: filename, status: "pending", uploaded_by: author,
      file_checksum: Digest::SHA256.file(path).hexdigest)
    BinImport::Importer.new(path, source_filename: filename, organization: default_organization).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
