# Autorização do download de arquivo. Exigir sessão já fecha a porta para quem está de fora,
# mas não impede um ator autenticado baixar o anexo de uma anotação que ele não pode ler —
# a URL é difícil de adivinhar, e só.
#
# O dono do blob é quem responde: o anexo de anotação pertence ao rich text de um
# CompanyNote, e daí se chega ao CNPJ e ao escopo. A planilha de um lote é tratada na fase
# dos lotes, onde a regra de quem vê qual arquivo é definida.
module BlobAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :authorize_blob_owner!
  end

  private

  def authorize_blob_owner!
    dono = @blob&.attachments&.first&.record
    return if dono.nil? # Blob recém-criado, ainda sem anexo: tratado no upload, não aqui.

    case dono
    when ActionText::RichText
      nota = CompanyNote.find_by(id: dono.record_id) if dono.record_type == "CompanyNote"
      return head :forbidden if nota.nil?

      head :not_found unless note_in_scope?(nota)
    when ImportBatch
      # A planilha original traz a carteira inteira de um Master num arquivo só: vale a
      # mesma regra do lote — os próprios envios e os que foram liberados.
      head :not_found unless ImportBatchPolicy.new(Current.user, dono).download_source_file?
    else
      head :forbidden
    end
  end

  def note_in_scope?(nota)
    return true if Current.user&.platform_admin?

    CompanyNotePolicy::Scope.new(Current.user, CompanyNote).resolve.exists?(id: nota.id)
  end
end
