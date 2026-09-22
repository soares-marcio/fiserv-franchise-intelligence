require "test_helper"

# Quem vê e quem mexe em cada lote. A planilha original é a carteira inteira de um Master
# num arquivo só — por isso a visibilidade aqui é nominal, e não "todos os lotes do meu
# Master": o autorizador libera arquivo a arquivo.
class BatchAccessTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    @canal = Channel.create!(external_id: "4444", name: "MASTER DOS LOTES")
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

  test "super admin enxerga e opera qualquer lote" do
    sign_in_as(admin_user)

    get import_batches_path
    assert_match(/dele\.xlsx/, response.body)

    get import_batch_path(@do_colega)
    assert_response :success
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
    outro = Channel.create!(external_id: "3333", name: "MASTER ALHEIO")
    autor = User.create!(email_address: "limitado@exemplo.com", name: "Limitado",
      password: Accounts::PASSWORD, permissions: [ Permission::BATCHES_UPLOAD ])
    autor.access_grants.create!(channel: outro)

    erro = assert_raises(ArgumentError) do
      import_synthetic_workbook_as(autor)
    end

    assert_match(/fora do seu acesso/, erro.message)
    assert_equal 0, MapSnapshot.count, "nada pode ser gravado antes da checagem"
  end

  test "com o Master no escopo, a importação segue normalmente" do
    autor = User.create!(email_address: "autorizado@exemplo.com", name: "Autorizado",
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
  def import_synthetic_workbook_as(autor, filename: "BIN_TESTE_20260811.xlsx")
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
    BinWorkbook.write(path)
    ImportBatch.create!(source_filename: filename, status: "pending", uploaded_by: autor,
      file_checksum: Digest::SHA256.file(path).hexdigest)
    BinImport::Importer.new(path, source_filename: filename).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
