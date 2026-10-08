module AuditEventsHelper
  # Cada ação em português, para a trilha ser lida por quem administra, e não por quem
  # escreveu o código.
  ACTION_LABELS = {
    "session.start" => "Entrou no portal",
    "session.end" => "Saiu do portal",
    "session.failed" => "Tentativa de entrada recusada",
    "mfa.failed" => "Código de verificação incorreto",
    "mfa.enrolled" => "Cadastrou o segundo fator",
    "mfa.recovery_code_used" => "Usou código de recuperação",
    "password.changed" => "Trocou a própria senha",
    "report.export" => "Exportou relatório",
    "batch.uploaded" => "Enviou planilha",
    "batch.approved" => "Aprovou importação",
    "batch.rejected" => "Recusou importação",
    "batch.discarded" => "Descartou lote",
    "batch.granted" => "Liberou arquivo a alguém",
    "batch.revoked" => "Revogou liberação de arquivo",
    "note.saved" => "Salvou anotação",
    "note.removed" => "Apagou anotação",
    "organization.created" => "Criou organização",
    "organization.named" => "Nomeou a organização",
    "organization.renamed" => "Renomeou organização",
    "organization.suspended" => "Suspendeu organização",
    "organization.reactivated" => "Reativou organização",
    "organization_admin.created" => "Criou administrador de organização",
    "channel.deleted" => "Apagou Master",
    "channel.restored" => "Restaurou Master",
    "sub_channel.deleted" => "Apagou MIC",
    "sub_channel.restored" => "Restaurou MIC",
    "user.created" => "Convidou alguém",
    "user.updated" => "Editou o acesso de alguém",
    "user.access_changed" => "Mudou permissões ou escopo de alguém",
    "user.access_validity_changed" => "Mudou a validade do acesso de alguém",
    "session.expired_access" => "Tentou entrar com o acesso vencido",
    "user.mfa_reset" => "Reiniciou o segundo fator de alguém",
    "user.deactivated" => "Desativou acesso de alguém",
    "user.reactivated" => "Reativou acesso de alguém"
  }.freeze

  # O que a plataforma pode ler dos metadados: lista fechada, e não de exclusão — chave nova
  # não chega à plataforma por esquecimento. Ficam de fora o nome do Master e do MIC, o nome
  # do arquivo, o recorte da exportação e todo texto escrito à mão (07/10/2026: o "Apagou
  # Master" mostrava o nome dele no histórico da plataforma).
  PLATFORM_METADATA_LABELS = {
    "report_id" => "REPORT_ID", "ecs" => "ECs", "mics" => "MICs", "lotes" => "lotes",
    "acessos" => "acessos", "caracteres" => "caracteres", "tela" => "tela", "formato" => "formato",
    "restantes" => "códigos restantes", "bloqueada" => "bloqueada", "email_tentado" => "e-mail tentado",
    "alvo" => "alvo", "mfa" => "segundo fator", "validade_antes" => "validade antes",
    "validade_depois" => "validade depois", "escopos_antes" => "escopos antes",
    "escopos_depois" => "escopos depois", "permissoes_antes" => "permissões antes",
    "permissoes_depois" => "permissões depois", "saindo" => "saindo", "entrando" => "entrando",
    "mudando_de_mic" => "mudando de MIC", "de" => "de", "para" => "para", "nome" => "nome"
  }.freeze
  # O motivo escrito pela plataforma (suspensão) é dela; o de uma recusa de importação é da
  # organização e pode citar cliente.
  PLATFORM_OWN_MOTIVE_PREFIX = "organization.".freeze

  def platform_metadata_summary(event)
    parts = event.metadata.to_h.filter_map do |key, value|
      label = PLATFORM_METADATA_LABELS[key.to_s]
      label ||= "motivo" if key.to_s == "motivo" && event.action.start_with?(PLATFORM_OWN_MOTIVE_PREFIX)
      next if label.nil?

      values = key.to_s.start_with?("permissoes_") ? Array(value).map { |item| Permission.label(item) } : Array(value)
      "#{label}: #{values.join(', ')}"
    end
    parts.empty? ? "—" : parts.join(" · ")
  end

  def audit_action_label(action)
    ACTION_LABELS.fetch(action, action)
  end

  def audit_metadata_summary(metadata)
    return "—" if metadata.blank?

    metadata.map { |key, value| "#{key.to_s.humanize.downcase}: #{Array(value).join(', ')}" }
      .join(" · ")
  end
end
