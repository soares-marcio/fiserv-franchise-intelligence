require "test_helper"

# O portal ganhou uma segunda porta de upload com a anotação. A primeira é a planilha, que
# valida extensão, tamanho e assinatura. Estes testes fixam a guarda desta, e o que mais
# importa neles é o `assert_no_difference`: a recusa tem de acontecer antes de o blob existir.
class NoteAttachmentsControllerTest < ActionDispatch::IntegrationTest
  def blob_params(content_type:, byte_size:, filename: "print.png")
    { blob: { filename:, byte_size:, checksum: Digest::MD5.base64digest("x"), content_type: } }
  end

  test "aceita imagem dentro do limite" do
    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      post rails_direct_uploads_path, params: blob_params(content_type: "image/png", byte_size: 1_024)
    end

    assert_response :success
    assert_predicate response.parsed_body["direct_upload"]["url"], :present?
  end

  test "recusa tipo fora da lista, sem criar o blob" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post rails_direct_uploads_path,
        params: blob_params(content_type: "application/x-msdownload", filename: "coisa.exe", byte_size: 1_024)
    end

    assert_response :unprocessable_entity
    assert_match(/imagem ou PDF/, response.parsed_body["error"])
  end

  test "recusa arquivo acima do limite, sem criar o blob" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post rails_direct_uploads_path,
        params: blob_params(content_type: "image/png", byte_size: NoteAttachmentsController::MAX_BYTES + 1)
    end

    assert_response :unprocessable_entity
    assert_match(/limite é 10 MB/, response.parsed_body["error"])
  end

  # A rota do app precisa vencer a do engine. Se a do Active Storage respondesse, o .exe
  # acima teria sido aceito — este teste é o que garante que a porta antiga não ficou aberta
  # ao lado da nova.
  test "a rota do Active Storage é a nossa, não a do engine" do
    assert_equal "note_attachments#create",
      Rails.application.routes.recognize_path("/rails/active_storage/direct_uploads", method: :post)
        .values_at(:controller, :action).join("#")
  end
end
