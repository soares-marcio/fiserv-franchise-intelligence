module EstablishmentsHelper
  BRAZILIAN_STATES = %w[
    AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO
  ].freeze
  CONTRACT_STATUSES = %w[Active Suspended].freeze

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

    css = case status.to_s
    when "Active" then "badge badge-success badge-sm"
    when "Suspended" then "badge badge-warning badge-sm"
    else "badge badge-ghost badge-sm"
    end
    content_tag(:span, status, class: css)
  end

  def manual_entry_value(name)
    params.dig(:manual_entry, name) || params.dig(:manual_entry, name.to_s)
  end
end
