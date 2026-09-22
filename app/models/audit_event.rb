# Trilha append-only. Nada no código atualiza nem apaga linha daqui: o que aconteceu ficou.
# O e-mail é copiado no instante do evento para o registro sobreviver à exclusão do usuário.
class AuditEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :channel, optional: true
  belongs_to :record, polymorphic: true, optional: true

  scope :recent, -> { order(created_at: :desc) }
end
