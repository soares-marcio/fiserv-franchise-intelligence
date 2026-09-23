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
    "note.saved" => "Salvou anotação",
    "note.removed" => "Apagou anotação"
  }.freeze

  def audit_action_label(action)
    ACTION_LABELS.fetch(action, action)
  end

  def audit_metadata_summary(metadata)
    return "—" if metadata.blank?

    metadata.map { |chave, valor| "#{chave.to_s.humanize.downcase}: #{Array(valor).join(', ')}" }
      .join(" · ")
  end
end
