require "test_helper"

# O anexo atravessa mais peças que o texto: o blob criado pelo upload direto, o sgid no corpo,
# a ligação com a anotação e o partial de exibição — que este projeto reescreveu, porque o
# padrão do Action Text pede uma variante e o processador está desligado aqui.
#
# O gesto de arrastar a imagem para dentro do editor é do Trix e não é exercitado: o seletor
# de arquivo dele é o nativo do sistema, fora do alcance do navegador de teste. O que estes
# testes cobrem é tudo o que vem depois dele, que é onde mora o risco do projeto.
class Operations::CompanyNoteAttachmentTest < ActiveSupport::TestCase
  CNPJ = "11222333000181".freeze

  test "a imagem anexada fica presa à anotação e volta como img, sem pedir variante" do
    blob = png_attachment
    note = Operations::SaveCompanyNote.call(organization: default_organization, cnpj: CNPJ, body: body_with(blob))

    assert_equal 1, note.body.body.attachments.size
    assert_equal blob, note.body.body.attachments.first.attachable

    html = note.body.to_s
    assert_match(/<img/, html)
    assert_match(/figure class="attachment attachment--preview/, html)
    # A prova de que o partial não pede variante: uma URL de representação apareceria aqui, e
    # com o variant_processor desligado ela devolveria o original sem avisar.
    assert_no_match(%r{/representations/}, html)
  end

  # PDF não é imagem: vira link com nome e tamanho, em vez de um <img> quebrado.
  test "PDF anexado vira link, não imagem" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4\n"), filename: "proposta.pdf", content_type: "application/pdf"
    )
    note = Operations::SaveCompanyNote.call(organization: default_organization, cnpj: CNPJ, body: body_with(blob))

    html = note.body.to_s
    assert_no_match(/<img/, html)
    assert_match(/proposta\.pdf/, html)
  end

  # Apagar a anotação leva os anexos junto: sem isso, o arquivo ficaria no disco sem nada que
  # aponte para ele, e a purga de órfãos só varre blob sem attachment nenhum.
  test "apagar a anotação leva o anexo junto" do
    Operations::SaveCompanyNote.call(organization: default_organization, cnpj: CNPJ, body: body_with(png_attachment))

    assert_difference -> { ActiveStorage::Attachment.count }, -1 do
      Operations::SaveCompanyNote.call(organization: default_organization, cnpj: CNPJ, body: "<div><br></div>")
    end
  end

  # Um anexo sozinho, sem uma palavra escrita, é anotação legítima — o print já diz o que
  # precisava ser dito. Não pode ser confundido com editor vazio.
  test "anexo sem texto não conta como anotação vazia" do
    note = Operations::SaveCompanyNote.call(organization: default_organization, cnpj: CNPJ, body: body_with(png_attachment))

    assert_not_nil note
    assert_predicate CompanyNote.find_by(cnpj: CNPJ), :present?
  end

  private

  def png_attachment
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(one_pixel_png), filename: "print.png", content_type: "image/png"
    )
  end

  # O corpo que o Trix monta depois de subir o arquivo: o anexo entra por sgid, não por URL.
  def body_with(blob)
    %(<div>Print da conversation.<action-text-attachment sgid="#{blob.attachable_sgid}">) +
      "</action-text-attachment></div>"
  end

  # PNG 1×1 montado na hora, com o CRC calculado: não há imagem versionada no repositório, e
  # bytes copiados à mão dariam um arquivo inválido.
  def one_pixel_png
    header = [ 1, 1, 8, 6, 0, 0, 0 ].pack("NNC5")
    pixel = Zlib::Deflate.deflate("\x00\x00\x00\x00\x00".b)
    "\x89PNG\r\n\x1a\n".b + chunk_png("IHDR", header) + chunk_png("IDAT", pixel) +
      chunk_png("IEND", "".b)
  end

  def chunk_png(kind, data)
    [ data.bytesize ].pack("N") + kind + data + [ Zlib.crc32(kind + data) ].pack("N")
  end
end
