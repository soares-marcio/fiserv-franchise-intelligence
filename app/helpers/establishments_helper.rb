module EstablishmentsHelper
  CONTRACT_STATUSES = %w[Active Suspended].freeze
  CONTRACT_STATUS_PRESENTATION = {
    "Active" => { label: "Ativo", tone: "success" },
    "Suspended" => { label: "Suspenso", tone: "warning" }
  }.freeze
  DATE_KIND_OPTIONS = [
    [ "credenciamento", "Credenciamento" ],
    [ "ativacao", "Ativação" ],
    [ "suspensao", "Suspensão" ]
  ].freeze
  DATE_KIND_TONES = {
    "credenciamento" => "teal",
    "ativacao" => "success",
    "suspensao" => "rose"
  }.freeze

  def formatted_cnpj(cnpj)
    digits = cnpj.to_s.gsub(/\D/, "")
    return present_or_dash(cnpj) unless digits.length == 14

    "#{digits[0..1]}.#{digits[2..4]}.#{digits[5..7]}/#{digits[8..11]}-#{digits[12..13]}"
  end

  def formatted_cep(cep)
    digits = cep.to_s.gsub(/\D/, "")
    return present_or_dash(cep) unless digits.length == 8

    "#{digits[0..4]}-#{digits[5..7]}"
  end

  def present_or_dash(value)
    return "—" if value.nil? || value == ""

    value
  end

  def boolean_label(value)
    return "—" if value.nil?

    value ? "Sim" : "Não"
  end

  def format_date(value)
    return "—" if value.blank?

    I18n.l(value.to_date)
  end

  def contract_status_badge(status)
    return content_tag(:span, "—", class: "opacity-50") if status.blank?

    presentation = CONTRACT_STATUS_PRESENTATION[status.to_s]
    css = presentation ? "badge badge-#{presentation[:tone]} badge-sm" : "badge badge-ghost badge-sm"
    content_tag(:span, contract_status_label(status), class: css)
  end

  def contract_status_label(status)
    CONTRACT_STATUS_PRESENTATION.dig(status.to_s, :label) || status.to_s
  end

  def contract_status_tone(status)
    CONTRACT_STATUS_PRESENTATION.dig(status.to_s, :tone) || "neutral"
  end
end
