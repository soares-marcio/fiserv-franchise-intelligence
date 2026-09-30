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
  # A organização do evento vem, nesta ordem, do parâmetro, do ator, do registro e do canal.
  # O ator vem primeiro de propósito: suporte feito pela plataforma sobre uma conta de
  # organização (reiniciar o segundo fator) fica sem organização — a plataforma vê, a
  # organização não. Inverter é uma linha, se um dia se decidir o contrário.
  def self.record(action, user: Current.user, record: nil, channel: nil, organization: nil, metadata: {},
    request: nil)
    channel ||= record.try(:channel)
    AuditEvent.create!(
      user:,
      # Cópia do e-mail no instante do evento: o registro sobrevive à exclusão do usuário.
      actor_email: user&.email_address || "sistema",
      action:,
      record_type: record&.class&.name,
      record_id: record&.id,
      channel:,
      organization: organization || user&.organization || record.try(:organization) || channel&.organization,
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
