# Anexos das anotações. O portal ganhou uma segunda porta de upload — a primeira é a planilha,
# que valida extensão, tamanho e assinatura ZIP — e esta precisa da sua própria guarda.
#
# A rota substitui a do Active Storage em vez de conviver com ela: uma rota nova deixaria
# `/rails/active_storage/direct_uploads` aberta ao lado, aceitando qualquer tipo e qualquer
# tamanho, que é justamente o que se quer fechar.
#
# A recusa acontece **antes** do super, porque é o super que cria o blob. Validar depois
# deixaria o registro no banco e o espaço reservado no disco.
class NoteAttachmentsController < ActiveStorage::DirectUploadsController
  ALLOWED_CONTENT_TYPES = %w[
    image/png image/jpeg image/gif image/webp application/pdf
  ].freeze
  MAX_BYTES = 10.megabytes

  rate_limit to: 20, within: 1.minute,
    with: -> { render json: { error: "Muitos envios em sequência. Aguarde um minuto." }, status: :too_many_requests }

  def create
    if (rejection_message = rejection(params[:blob]))
      render json: { error: rejection_message }, status: :unprocessable_entity
      return
    end

    super
  end

  private

  def rejection(blob)
    return "Envie um arquivo." if blob.blank?

    content_type = blob[:content_type].to_s
    unless ALLOWED_CONTENT_TYPES.include?(content_type)
      return "Anexo precisa ser imagem ou PDF, e este é #{content_type.presence || 'de content_type desconhecido'}."
    end

    byte_size = blob[:byte_size].to_i
    return if byte_size.positive? && byte_size <= MAX_BYTES

    "O anexo tem #{(byte_size / 1.megabyte.to_f).round(1)} MB e o limite é #{MAX_BYTES / 1.megabyte} MB."
  end
end
