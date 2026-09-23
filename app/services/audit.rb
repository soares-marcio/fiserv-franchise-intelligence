# Registro do que aconteceu no portal. Append-only por convenção: nada no código atualiza
# nem apaga linha de audit_events.
#
# Chamado dos controllers e das operações, nunca de callback de model — é o estilo do
# projeto, e também o que permite registrar a intenção ("exportou a tela X com o recorte Y")
# em vez de só a mudança de linha.
#
# O que nunca entra em metadata: CNPJ, faturamento, nome de cliente. A trilha diz quem fez o
# quê, e não repete o dado que a tela já protege — senão ela mesma vira um vazamento, e um
# que ninguém recorta por escopo.
class Audit
  def self.record(action, user: Current.user, record: nil, channel: nil, metadata: {}, request: nil)
    AuditEvent.create!(
      user:,
      # Cópia do e-mail no instante do evento: o registro sobrevive à exclusão do usuário.
      actor_email: user&.email_address || "sistema",
      action:,
      record_type: record&.class&.name,
      record_id: record&.id,
      channel: channel || record.try(:channel),
      metadata:,
      ip_address: request&.remote_ip,
      created_at: Time.current
    )
  rescue StandardError => error
    # A trilha não pode derrubar a ação que ela registra: perder o registro é ruim, perder a
    # operação do usuário é pior. A falha vai para o log, onde é visível.
    Rails.logger.error("[auditoria] #{action} não registrado: #{error.class}: #{error.message}")
    nil
  end
end
