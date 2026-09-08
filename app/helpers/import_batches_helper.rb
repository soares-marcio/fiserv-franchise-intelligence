module ImportBatchesHelper
  # Texto que o usuário envia ao administrador. Traz o que identifica a falha sem depender de
  # memória: arquivo, momento, lote, identificação do conteúdo e a mensagem inteira.
  def import_failure_report(batch)
    [
      "Falha na importação — Auditoria BIN",
      "Arquivo: #{batch.source_filename}",
      "Enviado em: #{batch.created_at.strftime('%d/%m/%Y %H:%M')}",
      "Lote ##{batch.id} · identificação do arquivo: #{batch.file_checksum.first(12)}",
      ("Canal: #{batch.channel.name}" if batch.channel),
      "Status: #{batch.status}",
      "",
      *batch.validation_errors
    ].compact.join("\n")
  end

  STATUS_PRESENTATION = {
    "validated" => { label: "Importado", tone: "success" },
    "failed" => { label: "Falhou", tone: "error" },
    "pending" => { label: "Importando", tone: "info" },
    "superseded" => { label: "Substituído", tone: "ghost" }
  }.freeze

  def import_status_badge(batch)
    return content_tag(:span, "Pendente", class: "badge badge-warning") if batch.stuck?

    presentation = STATUS_PRESENTATION.fetch(batch.status, { label: batch.status, tone: "ghost" })
    content_tag(:span, presentation[:label], class: "badge badge-#{presentation[:tone]}")
  end

  # Sem depender das traduções de distance_in_words, que o locale pt-BR não traz.
  def heartbeat_label(time)
    seconds = (Time.current - time).to_i
    return "agora há pouco" if seconds < 60
    return "há #{seconds / 60} min" if seconds < 3600

    "às #{time.strftime('%H:%M')}"
  end

  def days_label(days)
    days == 1 ? "1 dia" : "#{days} dias"
  end

  def last_file_headline(days)
    return "Nunca" if days.nil?
    return "Hoje" if days.zero?

    "há #{days_label(days)}"
  end

  def last_file_hint(days)
    return "Importe o primeiro arquivo BIN para começar." if days.nil?
    return "Arquivo recebido hoje." if days.zero?
    if days >= ImportBatch::STALE_AFTER_DAYS
      return "Sem arquivo novo há #{days_label(days)}, acima do limite de " \
        "#{ImportBatch::STALE_AFTER_DAYS} dias. Cobre a Fiserv."
    end

    "Dentro do esperado. O alerta começa em #{ImportBatch::STALE_AFTER_DAYS} dias."
  end
end
