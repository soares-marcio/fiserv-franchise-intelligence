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

  def nav_active?(*matches)
    matches.any? do |match|
      controller = match.fetch(:controller)
      actions = Array(match[:actions]).compact
      controller_name == controller.to_s &&
        (actions.empty? || actions.include?(action_name))
    end
  end

  def nav_link_class(*matches)
    [ "nav-link", ("is-active" if nav_active?(*matches)) ].compact.join(" ")
  end

  def breadcrumb_items
    [ breadcrumb_link("Início", root_path), *section_breadcrumb_items ]
  end

  def section_breadcrumb_items
    case controller_name
    when "reports" then reports_breadcrumb_items
    when "establishments" then establishments_breadcrumb_items
    when "import_batches" then import_batches_breadcrumb_items
    when "metabase" then [ breadcrumb_current("Metabase") ]
    else [ breadcrumb_current(content_for(:title).presence || "Página") ]
    end
  end

  def reports_breadcrumb_items
    case action_name
    when "index"
      [ breadcrumb_current("Faturamento") ]
    when "stalled"
      [ breadcrumb_current("Clientes parados") ]
    when "weekly"
      [ breadcrumb_current("Semanal") ]
    when "sub_channel"
      [ breadcrumb_link("Faturamento", reports_path),
        breadcrumb_current(@sub_channel&.name || "Subcanal") ]
    when "three_months"
      [ breadcrumb_current("Ganhos 3M") ]
    when "recurring"
      [ breadcrumb_current("Ganho recorrente") ]
    when "three_months_sub_channel"
      [ breadcrumb_link("Ganhos 3M", three_months_reports_path),
        breadcrumb_current(@sub_channel&.name || "Subcanal") ]
    else
      [ breadcrumb_current("Faturamento") ]
    end
  end

  def establishments_breadcrumb_items
    case action_name
    when "index"
      [ breadcrumb_current("Estabelecimentos") ]
    when "show"
      [ breadcrumb_link("Estabelecimentos", establishments_path),
        breadcrumb_current("EC #{@establishment&.ec || params[:id]}") ]
    else
      [ breadcrumb_current("Estabelecimentos") ]
    end
  end

  def import_batches_breadcrumb_items
    case action_name
    when "index"
      [ breadcrumb_current("Importar arquivo") ]
    when "show"
      [ breadcrumb_link("Importar arquivo", import_batches_path),
        breadcrumb_current(@import_batch&.source_filename || "Lote") ]
    else
      [ breadcrumb_current("Importar arquivo") ]
    end
  end

  # Sinal operacional presente em toda página: há quanto tempo a carteira recebeu arquivo.
  def header_file_status
    days = ImportBatch.days_since_last_file
    stale = days.nil? || days >= ImportBatch::STALE_AFTER_DAYS
    label = days.nil? ? "Sem arquivo importado" : "Arquivo #{last_file_headline(days).downcase}"
    link_to import_batches_path, class: "header-status", title: last_file_hint(days),
      data: { tone: stale ? "rose" : "green" } do
      safe_join([ tag.span(class: "status-dot", aria: { hidden: true }), label ], " ")
    end
  end

  def render_breadcrumbs
    content_tag(:nav, class: "breadcrumb-wrap", aria: { label: "Trilha de navegação" }) do
      content_tag(:ol, class: "breadcrumb-list") do
        safe_join(breadcrumb_items.map { |item| breadcrumb_item(item) })
      end
    end
  end

  def breadcrumb_link(label, path)
    { label:, path: }
  end

  def breadcrumb_current(label)
    { label:, current: true }
  end

  def breadcrumb_item(item)
    content_tag(:li, class: "breadcrumb-item") do
      if item[:current]
        content_tag(:span, item[:label], aria: { current: "page" })
      elsif item[:path] == root_path
        link_to icon_label("house", item[:label], css: "breadcrumb-icon"), item[:path]
      else
        link_to item[:label], item[:path]
      end
    end
  end

  # Ícone Phosphor (regular) inline, de vendor/icons/phosphor/regular. Decorativo por
  # padrão: o texto ao lado é quem dá o significado.
  def icon(name, css: "icon-inline")
    @inline_icons ||= {}
    svg = @inline_icons[name] ||= Rails.root.join("vendor/icons/phosphor/regular/#{name}.svg").read
    svg.sub("<svg ", %(<svg class="#{css}" aria-hidden="true" focusable="false" )).html_safe
  end

  def icon_label(name, text, css: "btn-icon")
    safe_join([ icon(name, css:), text ])
  end

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

  def variation_chip(previous, current, novo: nil)
    direction = variation_direction(previous, current)
    return zero_base_chip(current, novo:) if direction == :unavailable

    verb = VARIATION_VERBS.fetch(direction)
    value = signed_variation(previous, current)
    content_tag(:span, class: "variation-chip variation-chip--#{direction}",
      aria: { label: "#{verb.downcase} #{value}" }) do
      safe_join([ variation_icon_tip(direction, verb),
        content_tag(:span, value, class: "variation-chip__value") ])
    end
  end

  # Base zero não tem percentual possível (divisão por zero), mas o caso é descritível
  # em texto, na mesma anatomia dos chips existentes. Três leituras: "Novo" quando o EC
  # foi ativado neste mês ou no anterior e vendeu; "Voltou a vender" quando é antigo,
  # estava zerado e vendeu (mora na aba de queda — é atenção, não crescimento); e
  # "Sem venda" quando segue zerado. `novo: nil` preserva a leitura otimista para
  # chamadores sem data, como a listagem por subcanal.
  def zero_base_chip(current, novo: nil)
    if current.to_d.positive?
      if novo == false
        content_tag(:span, class: "variation-chip variation-chip--flat",
          aria: { label: "voltou a vender: sem venda no mês anterior, ativação antiga" }) do
          safe_join([ variation_icon_tip(:flat, "Sem venda no mês anterior; ativação antiga"),
            content_tag(:span, "Voltou a vender", class: "variation-chip__value") ])
        end
      else
        content_tag(:span, class: "variation-chip variation-chip--up",
          aria: { label: "novo: primeira venda na base" }) do
          safe_join([ variation_icon_tip(:up, "Primeira venda na base"),
            content_tag(:span, "Novo", class: "variation-chip__value") ])
        end
      end
    else
      content_tag(:span, class: "variation-chip variation-chip--flat",
        aria: { label: "sem venda nos dois períodos" }) do
        safe_join([ variation_icon_tip(:flat, "Zerado nos dois períodos"),
          content_tag(:span, "Sem venda", class: "variation-chip__value") ])
      end
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

  # A opção nomeia o M0 escolhido e a janela que ele abre: quem credenciou em junho é
  # apurado em junho, julho e agosto. Quando a janela atravessa o ano, os dois aparecem.
  def three_month_window_label(first_period)
    first_period = first_period.to_date
    last_period = first_period >> 2
    first = I18n.l(first_period, format: "%B")
    last = I18n.l(last_period, format: "%B de %Y")
    return "#{first} a #{last}".capitalize if first_period.year == last_period.year

    "#{first} de #{first_period.year} a #{last}".capitalize
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

  # NET MDR em pontos percentuais, truncado em duas casas — nunca arredondado, para não
  # sugerir uma faixa de remuneração que o valor real não atinge.
  def net_mdr_label(value, status = nil)
    return "Inativo" if status.present?
    return if value.blank?

    "#{number_with_precision(value.to_d.truncate(2), precision: 2, separator: ',')}%"
  end

  # Presença dos tipos de equipamento do Mapa, no vocabulário da planilha. Sem nenhum dado
  # (EC fora do Mapa), não afirma nada; com dado e nenhum equipamento, diz isso.
  def equipment_summary(has_payment_link, smart_pos_count, other_pos_count)
    return if has_payment_link.nil? && smart_pos_count.nil? && other_pos_count.nil?

    labels = []
    labels << "Link pgto" if has_payment_link
    # Decisão do usuário: Smart POS e Demais POS aparecem como um único "POS".
    labels << "POS" if smart_pos_count.to_i.positive? || other_pos_count.to_i.positive?
    labels.any? ? labels.join(" · ") : "Sem equipamentos"
  end

  def brl(amount)
    # Espaço não separável entre "R$" e o número: o valor nunca quebra em duas linhas.
    number_to_currency(amount.to_d, unit: "R$", separator: ",", delimiter: ".",
      format: "%u\u00A0%n")
  end
end
