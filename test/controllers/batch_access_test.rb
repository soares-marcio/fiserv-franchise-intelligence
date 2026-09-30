require "test_helper"

# Quem vê e quem mexe em cada lote. A planilha original é a carteira inteira de um Master
# num arquivo só — por isso a visibilidade aqui é nominal, e não "todos os lotes do meu
# Master": o autorizador libera arquivo a arquivo.
class BatchAccessTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @canal = Channel.create!(organization: default_organization, external_id: "4444", name: "MASTER DOS LOTES")
    @dono = scoped_user(permissions: todas_de_lote, channel: @canal, email: "dono@exemplo.com")
    @colega = scoped_user(permissions: todas_de_lote, channel: @canal, email: "colega@exemplo.com")

    @meu = ImportBatch.create!(source_filename: "meu.xlsx", file_checksum: "meu-1",
      status: "failed", channel: @canal, uploaded_by: @dono)
    @do_colega = ImportBatch.create!(source_filename: "dele.xlsx", file_checksum: "dele-1",
      status: "failed", channel: @canal, uploaded_by: @colega)
  end

  test "a listagem mostra só os próprios envios" do
    sign_in_as(@dono)

    get import_batches_path

    assert_response :success
    assert_match(/meu\.xlsx/, response.body)
    assert_no_match(/dele\.xlsx/, response.body)
  end

  # 404, e não 403: dizer "existe, mas não é seu" já conta que aquele arquivo foi enviado.
  test "lote de outro ator responde 404" do
    sign_in_as(@dono)

    get import_batch_path(@do_colega)

    assert_response :not_found
  end

  test "lote liberado nominalmente passa a aparecer e a abrir" do
    BatchGrant.create!(user: @dono, import_batch: @do_colega, created_by: @colega)
    sign_in_as(@dono)

    get import_batches_path
    assert_match(/dele\.xlsx/, response.body)

    get import_batch_path(@do_colega)
    assert_response :success
  end

  # Ver não é mexer: mesmo com o lote liberado e com as chaves, reprocessar e descartar
  # continuam sendo só de quem enviou — descartar é irreversível e reprocessar reescreve a
  # consolidação do Master.
  test "lote liberado não pode ser reprocessado, ajustado nem descartado" do
    BatchGrant.create!(user: @dono, import_batch: @do_colega, created_by: @colega)
    sign_in_as(@dono)

    post reprocess_import_batch_path(@do_colega)
    assert_response :forbidden

    patch update_cutoff_import_batch_path(@do_colega), params: { max_known_day: 10 }
    assert_response :forbidden

    assert_no_difference -> { ImportBatch.count } do
      delete import_batch_path(@do_colega)
    end
    assert_response :forbidden
  end

  test "no próprio lote, as ações funcionam" do
    sign_in_as(@dono)

    assert_difference -> { ImportBatch.count }, -1 do
      delete import_batch_path(@meu)
    end
  end

  # A planilha original vale o mesmo que o lote: quem não alcança o lote não baixa o arquivo.
  test "a planilha enviada segue a regra do lote" do
    @do_colega.source_file.attach(io: StringIO.new("planilha"), filename: "dele.xlsx",
      content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    sign_in_as(@dono)

    get rails_blob_path(@do_colega.source_file, disposition: "attachment")
    assert_response :not_found

    BatchGrant.create!(user: @dono, import_batch: @do_colega, created_by: @colega)
    get rails_blob_path(@do_colega.source_file, disposition: "attachment")
    assert_response :redirect
  end

  # A revisão mostra o diff do Master inteiro. Um aprovador com um MIC só veria os outros —
  # por isso o lote em revisão nem entra no alcance dele (homologação de 29/09/2026).
  test "aprovador com um MIC só não alcança a revisão; com o Master inteiro, alcança" do
    mic = SubChannel.create!(channel: @canal, name: "MIC UM")
    pendente = ImportBatch.create!(source_filename: "pendente.xlsx", file_checksum: "pend-1",
      status: "pending_review", channel: @canal, uploaded_by: @colega)
    aprova = [ Permission::BATCHES_READ, Permission::BATCHES_APPROVE ]

    do_mic = scoped_user(permissions: aprova, sub_channel: mic, email: "mic@exemplo.com")
    sign_in_as(do_mic)
    get import_batches_path
    assert_no_match(/pendente\.xlsx/, response.body)
    get review_import_batch_path(pendente)
    assert_response :not_found
    sign_out

    inteiro = scoped_user(permissions: aprova, channel: @canal, email: "inteiro@exemplo.com")
    sign_in_as(inteiro)
    get import_batches_path
    assert_match(/pendente\.xlsx/, response.body)
    assert ImportBatchPolicy.new(inteiro, pendente).review?
  end

  # Liberar é administrar acesso: exige a chave de convidar, alcançar o lote e o Master
  # inteiro — de quem libera e de quem recebe.
  test "liberar um arquivo: só a quem tem o Master inteiro, e revogar tira na hora" do
    mic = SubChannel.create!(channel: @canal, name: "MIC UM")
    autorizador = scoped_user(permissions: todas_de_lote + [ Permission::USERS_INVITE ],
      channel: @canal, email: "autorizador@exemplo.com")
    lote = ImportBatch.create!(source_filename: "liberavel.xlsx", file_checksum: "lib-1",
      status: "validated", channel: @canal, uploaded_by: autorizador)
    do_mic = scoped_user(permissions: [ Permission::BATCHES_READ ], sub_channel: mic, email: "mic@exemplo.com")
    sign_in_as(autorizador)

    get import_batch_path(lote)
    assert_match(/Quem vê este arquivo/, response.body)
    assert_match(/colega@exemplo\.com/, response.body, "quem tem o Master inteiro é oferecido")
    assert_no_match(/mic@exemplo\.com/, response.body, "quem tem um MIC não é oferecido")

    assert_difference -> { BatchGrant.count } do
      post import_batch_batch_grants_path(lote), params: { user_id: @colega.to_param }
    end
    assert_no_difference -> { BatchGrant.count } do
      post import_batch_batch_grants_path(lote), params: { user_id: do_mic.to_param }
    end
    assert_match(/Master .* inteiro/, flash[:alert])
    sign_out

    sign_in_as(@colega)
    get import_batches_path
    assert_match(/liberavel\.xlsx/, response.body)
    sign_out

    # Reentrar com quem já entrou exige outra janela do TOTP: o código não vale duas vezes.
    travel 31.seconds
    sign_in_as(autorizador)
    assert_difference -> { BatchGrant.count }, -1 do
      delete import_batch_batch_grant_path(lote, BatchGrant.find_by!(user: @colega, import_batch: lote))
    end
    sign_out

    travel 31.seconds
    sign_in_as(@colega)
    get import_batch_path(lote)
    assert_response :not_found
  end

  test "sem a chave de convidar, a seção de liberação não aparece e o POST é recusado" do
    sign_in_as(@dono)

    get import_batch_path(@meu)
    assert_no_match(/Quem vê este arquivo/, response.body)

    post import_batch_batch_grants_path(@meu), params: { user_id: @colega.to_param }
    assert_response :forbidden
  end

  test "super admin enxerga e opera qualquer lote" do
    sign_in_as(admin_user)

    get import_batches_path
    assert_match(/dele\.xlsx/, response.body)

    get import_batch_path(@do_colega)
    assert_response :success
  end

  # Quem só envia precisa da tela para enviar e para acompanhar o próprio lote; a planilha
  # original, que é a carteira inteira, continua atrás de "Ver lotes".
  test "só 'Enviar planilha' abre a tela de importação com os próprios envios, sem baixar a planilha" do
    remetente = scoped_user(permissions: [ Permission::BATCHES_UPLOAD ], channel: @canal, email: "envia@exemplo.com")
    proprio = ImportBatch.create!(source_filename: "enviado.xlsx", file_checksum: "envia-1",
      status: "failed", channel: @canal, uploaded_by: remetente)
    sign_in_as(remetente)

    get reports_path
    assert_select "nav.primary-nav a[href=?]", import_batches_path, text: /Importar arquivo/

    get import_batches_path
    assert_response :success
    assert_match(/enviado\.xlsx/, response.body)
    assert_no_match(/meu\.xlsx|dele\.xlsx/, response.body)

    get import_batch_path(proprio)
    assert_response :success

    # O download passa pelo Active Storage e responde 404 pela mesma policy.
    assert_not ImportBatchPolicy.new(remetente, proprio).download_source_file?
    assert ImportBatchPolicy.new(@dono, @meu).download_source_file?
  end

  private

  def todas_de_lote
    [ Permission::BATCHES_READ, Permission::BATCHES_UPLOAD, Permission::BATCHES_ADJUST,
      Permission::BATCHES_DISCARD ]
  end
end

# O Master do arquivo só se conhece depois do parse: a checagem de escopo acontece ali,
# antes de gravar qualquer linha.
class BatchUploadScopeTest < ActiveSupport::TestCase
  test "planilha de Master fora do escopo é recusada com mensagem clara" do
    outro = Channel.create!(organization: default_organization, external_id: "3333", name: "MASTER ALHEIO")
    autor = User.create!(organization: default_organization, email_address: "limitado@exemplo.com", name: "Limitado",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])
    autor.access_grants.create!(channel: outro)

    erro = assert_raises(ArgumentError) do
      import_synthetic_workbook_as(autor)
    end

    assert_match(/administrador da organização/, erro.message,
      "Master novo: um colaborador não o inaugura, mesmo com concessão em outro Master")
    assert_equal 0, MapSnapshot.count, "nada pode ser gravado antes da checagem"
  end

  # A planilha substitui a carteira inteira do Master: um MIC dele não basta para enviá-la.
  # O canal é criado antes com a identidade da planilha sintética, para o MIC existir e o
  # resolvedor reaproveitá-lo.
  test "com um MIC só do Master, o envio é recusado antes de gravar qualquer linha" do
    canal = Channel.create!(organization: default_organization, external_id: BinWorkbook::REPORT_ID, name: BinWorkbook::CANAL)
    mic = SubChannel.create!(channel: canal, name: "MIC ALFA")
    autor = User.create!(organization: default_organization, email_address: "parcial@exemplo.com", name: "Parcial",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])
    autor.access_grants.create!(channel: canal, sub_channel: mic)

    erro = nil
    assert_no_difference -> { MapSnapshot.count } do
      erro = assert_raises(ArgumentError) { import_synthetic_workbook_as(autor) }
    end

    assert_match(/inteiro/, erro.message)
  end

  test "com o Master no escopo, a importação segue normalmente" do
    autor = User.create!(organization: default_organization, email_address: "autorizado@exemplo.com", name: "Autorizado",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])

    # O canal nasce no próprio import; a concessão é dada depois, e o segundo envio passa.
    batch = import_synthetic_workbook
    autor.access_grants.create!(channel: batch.channel)

    assert_nothing_raised { import_synthetic_workbook_as(autor, filename: "BIN_TESTE_20260812.xlsx") }
  end

  private

  # O lote precisa nascer com o checksum do próprio arquivo: é por ele que o importador
  # reencontra o registro e descobre quem enviou. Com outro valor, ele criaria um lote novo
  # sem autor — e a checagem de escopo não teria a quem se aplicar.
  #
  # As lojas levam um dia a mais de faturamento: a planilha sintética só varia pelo
  # instante de criação, em segundos, e o segundo envio no mesmo segundo do primeiro
  # repetiria o checksum — o que na CI acontecia.
  def import_synthetic_workbook_as(autor, filename: "BIN_TESTE_20260811.xlsx")
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
    lojas = BinWorkbook.default_lojas.map do |loja|
      loja.class.new(**loja.to_h.merge(dias_atual: loja.dias_atual.merge(20 => 77)))
    end
    BinWorkbook.write(path, lojas:)
    ImportBatch.create!(source_filename: filename, status: "pending", uploaded_by: autor,
      file_checksum: Digest::SHA256.file(path).hexdigest)
    BinImport::Importer.new(path, source_filename: filename, organization: default_organization).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
