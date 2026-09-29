# Liberação de um lote específico a um usuário: é assim que alguém vê um arquivo que não
# enviou. Sem isso, a tela de importação mostra só os próprios envios.
class BatchGrant < ApplicationRecord
  belongs_to :user
  belongs_to :import_batch
  belongs_to :created_by, class_name: "User", optional: true

  validates :user_id, uniqueness: { scope: :import_batch_id, message: "já tem este arquivo liberado" }
  validate :recipient_has_whole_channel

  private

  # A planilha é a carteira inteira do Master: liberá-la a quem tem só um MIC entregaria os
  # outros. A regra fica no modelo, e não só na tela, para valer também por console.
  def recipient_has_whole_channel
    return if user.nil? || import_batch.nil?
    if import_batch.channel_id.nil?
      errors.add(:base, "o lote ainda não tem Master identificado; libere depois do processamento")
      return
    end
    return if AccessScope.for(user).whole?(import_batch.channel_id)

    errors.add(:base, "#{user.name} não tem o Master \"#{import_batch.channel.name}\" inteiro — " \
      "a planilha é a carteira toda, e só pode ser liberada a quem tem esse Master inteiro")
  end
end
