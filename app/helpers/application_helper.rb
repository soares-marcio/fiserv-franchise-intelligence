module ApplicationHelper
  def aligned_variation(previous, current)
    previous = previous.to_d
    current = current.to_d
    return "—" if previous.zero?

    number_to_percentage((current / previous - 1) * 100, precision: 1)
  end

  def variation_direction(previous, current)
    previous = previous.to_d
    current = current.to_d
    return :unavailable if previous.zero?
    return :up if current > previous
    return :down if current < previous

    :flat
  end

  def signed_variation(previous, current)
    label = aligned_variation(previous, current)
    return label if label == "—" || label.start_with?("-", "+")

    "+#{label}"
  end

  # Phosphor Icons duotone, MIT: https://phosphoricons.com
  PHOSPHOR_ICONS = {
    up: "trend-up-duotone.svg",
    down: "trend-down-duotone.svg",
    flat: "minus-duotone.svg"
  }.freeze

  VARIATION_VERBS = { up: "Subiu", down: "Caiu", flat: "Estável" }.freeze

  def phosphor_icon(direction)
    @phosphor_icons ||= {}
    @phosphor_icons[direction] ||= begin
      svg = Rails.root.join("vendor/icons/phosphor", PHOSPHOR_ICONS.fetch(direction)).read
      svg.sub("<svg ", '<svg class="variation-icon" aria-hidden="true" ').html_safe
    end
  end

  def variation_icon_tip(direction, verb)
    content_tag(:span, phosphor_icon(direction),
      class: "tooltip tooltip-left variation-icon-tip",
      data: { tip: verb }, tabindex: 0)
  end

  def variation_chip(previous, current)
    direction = variation_direction(previous, current)
    if direction == :unavailable
      return content_tag(:span, "—", class: "variation-chip variation-chip--empty")
    end

    verb = VARIATION_VERBS.fetch(direction)
    value = signed_variation(previous, current)
    content_tag(:span, class: "variation-chip variation-chip--#{direction}",
      aria: { label: "#{verb.downcase} #{value}" }) do
      safe_join([ variation_icon_tip(direction, verb),
        content_tag(:span, value, class: "variation-chip__value") ])
    end
  end

  def variation_headline(previous, current)
    direction = variation_direction(previous, current)
    return "—" if direction == :unavailable

    verb = VARIATION_VERBS.fetch(direction)
    safe_join([ variation_icon_tip(direction, verb), signed_variation(previous, current) ], " ")
  end

  def period_option_label(date)
    I18n.l(date.to_date, format: "%B de %Y")
  end

  def day_range_label(from_day, to_day)
    from_day = from_day.to_i
    to_day = to_day.to_i
    return "até o dia #{to_day}" if from_day <= 1

    "dias #{from_day} a #{to_day}"
  end

  def period_picker_label(period, from_day, to_day)
    month = period_option_label(period)
    from_day = from_day.to_i
    to_day = to_day.to_i
    return "#{from_day} de #{month}" if from_day == to_day

    "#{from_day} a #{to_day} de #{month}"
  end

  def iso_range_label(from_date, to_date)
    return "Escolher intervalo" if from_date.blank?

    from_label = I18n.l(from_date.to_date)
    to_label = I18n.l((to_date.presence || from_date).to_date)
    return from_label if from_label == to_label

    "#{from_label} a #{to_label}"
  end

  def variation_metric_tone(previous, current)
    { up: "green", down: "rose", flat: "gold" }[variation_direction(previous, current)]
  end

  def brl(amount)
    number_to_currency(amount.to_d, unit: "R$", separator: ",", delimiter: ".")
  end

  def compact_revenue_days(payload)
    days = revenue_days_hash(payload)
    return "—" if days.blank?

    days.sort_by { |day, _| day.to_i }.map { |day, amount| "D#{day} #{brl(amount)}" }.join(" · ")
  end

  def comparable_revenue_days(payload, cutoff_day)
    return {} unless cutoff_day

    revenue_days_hash(payload).select { |day, _| day.to_i <= cutoff_day.to_i }
  end

  def revenue_days_json(payload)
    revenue_days_hash(payload).transform_keys(&:to_s).sort_by { |day, _| day.to_i }.to_h.to_json
  end

  def revenue_days_hash(payload)
    case payload
    when Hash then payload
    when String then JSON.parse(payload)
    else {}
    end
  rescue JSON::ParserError
    {}
  end
end
