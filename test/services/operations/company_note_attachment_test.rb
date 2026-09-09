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
    blob = anexo_png
    nota = Operations::SaveCompanyNote.call(cnpj: CNPJ, body: corpo_com(blob))

    assert_equal 1, nota.body.body.attachments.size
    assert_equal blob, nota.body.body.attachments.first.attachable

    html = nota.body.to_s
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
    nota = Operations::SaveCompanyNote.call(cnpj: CNPJ, body: corpo_com(blob))

    html = nota.body.to_s
    assert_no_match(/<img/, html)
    assert_match(/proposta\.pdf/, html)
  end

  # Apagar a anotação leva os anexos junto: sem isso, o arquivo ficaria no disco sem nada que
  # aponte para ele, e a purga de órfãos só varre blob sem attachment nenhum.
  test "apagar a anotação leva o anexo junto" do
    Operations::SaveCompanyNote.call(cnpj: CNPJ, body: corpo_com(anexo_png))

    assert_difference -> { ActiveStorage::Attachment.count }, -1 do
      Operations::SaveCompanyNote.call(cnpj: CNPJ, body: "<div><br></div>")
    end
  end

  # Um anexo sozinho, sem uma palavra escrita, é anotação legítima — o print já diz o que
  # precisava ser dito. Não pode ser confundido com editor vazio.
  test "anexo sem texto não conta como anotação vazia" do
    nota = Operations::SaveCompanyNote.call(cnpj: CNPJ, body: corpo_com(anexo_png))

    assert_not_nil nota
    assert_predicate CompanyNote.find_by(cnpj: CNPJ), :present?
  end

  private

  def anexo_png
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(png_de_um_pixel), filename: "print.png", content_type: "image/png"
    )
  end

  # O corpo que o Trix monta depois de subir o arquivo: o anexo entra por sgid, não por URL.
  def corpo_com(blob)
    %(<div>Print da conversa.<action-text-attachment sgid="#{blob.attachable_sgid}">) +
      "</action-text-attachment></div>"
  end

  # PNG 1×1 montado na hora, com o CRC calculado: não há imagem versionada no repositório, e
  # bytes copiados à mão dariam um arquivo inválido.
  def png_de_um_pixel
    cabecalho = [ 1, 1, 8, 6, 0, 0, 0 ].pack("NNC5")
    pixel = Zlib::Deflate.deflate("\x00\x00\x00\x00\x00".b)
    "\x89PNG\r\n\x1a\n".b + chunk_png("IHDR", cabecalho) + chunk_png("IDAT", pixel) +
      chunk_png("IEND", "".b)
  end

  def chunk_png(tipo, dados)
    [ dados.bytesize ].pack("N") + tipo + dados + [ Zlib.crc32(tipo + dados) ].pack("N")
  end
end
