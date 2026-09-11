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
      [ breadcrumb_current("Clover Capital") ]
    when "weekly"
      [ breadcrumb_current("Semanal") ]
    when "sub_channel"
      [ breadcrumb_link("Faturamento", reports_path),
        breadcrumb_current(@sub_channel&.name || "MIC") ]
    when "three_months"
      [ breadcrumb_current("Ganhos 3M") ]
    when "recurring"
      [ breadcrumb_current("Ganho recorrente") ]
    when "three_months_sub_channel"
      [ breadcrumb_link("Ganhos 3M", three_months_reports_path),
        breadcrumb_current(@sub_channel&.name || "MIC") ]
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
        breadcrumb_current(client_crumb_label) ]
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
        link_to icon("house", css: "breadcrumb-icon"), item[:path], aria: { label: item[:label] }
      else
        link_to item[:label], item[:path]
      end
    end
  end

  # Ícone Phosphor (regular) inline, de vendor/icons/phosphor/regular. Decorativo por
  # padrão: o texto ao lado é quem dá o significado.
  # O peso existe porque a seta do stepper precisa de traço grosso para se ver sobre o
  # laranja; os demais ícones continuam em regular, que é o padrão da casca.
  def icon(name, css: "icon-inline", weight: "regular")
    @inline_icons ||= {}
    svg = @inline_icons["#{weight}/#{name}"] ||=
      Rails.root.join("vendor/icons/phosphor/#{weight}/#{name}.svg").read
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

  # Master é como a tela chama o canal — o vocabulário do negócio, e o que os próprios dados
  # dizem: o canal da carteira se chama "MASTER FRANQUEADO ...". A exceção é o canal fictício,
  # que nasce com o nome da coluna que faltou na planilha: no banco ele continua "SEM CANAL",
  # que é o que o analista procura no arquivo e o que a mensagem de import cita.
  def channel_name(channel)
    return if channel.nil?

    channel.name == BinImport::ChannelResolver::FALLBACK_NAME ? "SEM MASTER" : channel.name
  end

  # Seta do calendário: link quando existe competência para onde ir, botão apagado quando
  # não existe. Some-lo faria o seletor pular de lugar ao chegar na ponta da série.
  def calendar_step(period, icon_name, label)
    if period.nil?
      return content_tag(:span, icon(icon_name, css: "stepper-icon", weight: "bold"),
        class: "btn btn--field is-disabled", aria: { hidden: true })
    end

    link_to icon(icon_name, css: "stepper-icon", weight: "bold"),
      weekly_reports_path(period: period.to_s, channel_id: params[:channel_id].presence),
      class: "btn btn--field", aria: { label: }
  end

  # Caret que troca o dia dentro do modal. Mira o próprio frame, então o diálogo continua
  # aberto; na ponta da cobertura vira botão apagado, como as setas da competência.
  def day_step(day, icon_name, label)
    if day.nil?
      return content_tag(:span, icon(icon_name, css: "stepper-icon", weight: "bold"),
        class: "btn btn--field is-disabled", aria: { hidden: true })
    end

    link_to icon(icon_name, css: "stepper-icon", weight: "bold"),
      weekly_day_report_path(day:, period: params[:period].presence, channel_id: params[:channel_id].presence),
      class: "btn btn--field", aria: { label: },
      data: { turbo_frame: "day_companies" }
  end

  # Intensidade da célula do calendário em cinco faixas, não num gradiente contínuo: cinco
  # tons se distinguem de relance, e o que se quer é ver o padrão da semana sem ler número.
  # Dia zerado fica sem preenchimento — ausência de venda não é um tom de laranja.
  def calendar_heat(revenue, max_revenue)
    revenue = revenue.to_d
    max_revenue = max_revenue.to_d
    return 0 if revenue <= 0 || max_revenue <= 0

    [ (revenue / max_revenue * 5).ceil, 5 ].min
  end

  # A ficha é do cliente: a trilha nomeia o cliente, com o CNPJ como recurso quando o cadastro
  # do Mapa não trouxe nome.
  def client_crumb_label
    snapshot = @snapshot
    nome = snapshot&.trade_name.presence || snapshot&.legal_name.presence
    nome || (@company ? formatted_cnpj(@company.cnpj) : params[:id])
  end

  def period_option_label(date)
    I18n.l(date.to_date, format: "%B de %Y")
  end

  # A opção nomeia o M0 escolhido e a janela que ele abre: quem credenciou em junho é
  # apurado em junho, julho e agosto. Quando a janela atravessa o ano, os dois aparecem.
  def three_month_window_label(first_period, last_period = nil)
    first_period = first_period.to_date
    last_period = (last_period || first_period >> 2).to_date
    first = I18n.l(first_period, format: "%B")
    last = I18n.l(last_period, format: "%B de %Y")
    return "#{first} a #{last}".capitalize if first_period.year == last_period.year

    "#{first} de #{first_period.year} a #{last}".capitalize
  end

  # Coluna ordenável sem indicador não se anuncia: quem não passa o mouse não descobre que
  # dá para clicar. Ícones Phosphor, como o resto da casca: caret-up-down em repouso e o
  # sentido na coluna ativa.
  SORT_ICONS = { idle: "caret-up-down", "desc" => "caret-down", "asc" => "caret-up" }.freeze

  def sort_indicator(column, current_sort, current_direction)
    ativa = column == current_sort
    nome = ativa ? SORT_ICONS.fetch(current_direction) : SORT_ICONS.fetch(:idle)
    tag.span(icon(nome, css: "sort-icon"), class: "sort-indicator #{"is-idle" unless ativa}")
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

  # Blocos de páginas do paginador, cada bloco com páginas contíguas: a primeira, uma
  # vizinhança da atual e a última. Entre blocos a tela escreve "…". Listar todas não é
  # navegação — 302 clientes a 10 por página dão 31 páginas, e uma parede de números.
  PAGINATION_WINDOW = 5

  def pagination_page_groups(page, total_pages)
    total = total_pages.to_i
    return [] if total < 2

    atual = page.to_i.clamp(1, total)
    numeros = pagination_numbers(atual, total)
    # Salto de uma página só não merece "…": o número ocupa o mesmo espaço e é clicável.
    numeros.flat_map { |numero| pagination_fill(numeros, numero) }
      .slice_when { |anterior, seguinte| seguinte - anterior > 1 }.to_a
  end

  def pagination_numbers(atual, total)
    return (1..total).to_a if total <= PAGINATION_WINDOW + 2

    primeira = (atual - PAGINATION_WINDOW / 2).clamp(1, total - PAGINATION_WINDOW + 1)
    ([ 1, total ] + (primeira...(primeira + PAGINATION_WINDOW)).to_a).uniq.sort
  end

  def pagination_fill(numeros, numero)
    return [ numero, numero + 1 ] if numeros.include?(numero + 2) && numeros.exclude?(numero + 1)

    [ numero ]
  end

  # Net MDR do cliente na listagem por subcanal: entra só porcentagem positiva (pedido do
  # usuário, 10/09/2026). Quando os ECs do mesmo CNPJ declaram alíquotas positivas
  # diferentes — 5 CNPJs da carteira real, e num deles de 0,62% a 2,53% — a célula mostra a
  # faixa. Escolher um dos valores esconderia quatro vezes a diferença.
  def client_net_mdr_label(minimum, maximum)
    return if minimum.blank?

    menor = net_mdr_label(minimum)
    maior = net_mdr_label(maximum)
    menor == maior ? menor : "#{menor} a #{maior}"
  end

  # A melhor conversa é de cada EC, e 116 dos 302 clientes da carteira têm mais de um texto
  # diferente. A consulta os traz todos num JSON rotulado pelo EC; o parse fica aqui para a
  # tela não conhecer o formato da coluna.
  def client_conversations(raw)
    return [] if raw.blank?

    JSON.parse(raw)
  end

  # Famílias nomeadas de terminal do Mapa; Smart POS e Demais POS aparecem como um
  # único "POS" (decisão do usuário). "QTDE OUTROS TERMINAIS" é tratada à parte.
  EQUIPMENT_COUNTS = {
    "POS" => %w[smart_pos_count other_pos_count],
    "Tap on phone" => %w[tap_on_phone_count],
    "MPS" => %w[mps_count],
    "PIN" => %w[pin_count],
    "TEF" => %w[tef_count]
  }.freeze

  # Inventário curto dos equipamentos do Mapa, com as quantidades da planilha: "2 TEF",
  # "1 POS". O guarda-chuva "outros terminais" sozinho não nomeia nada, então vira
  # "1 terminal"; ao lado de uma família nomeada, "+1 outro". Sem nenhum dado (EC fora
  # do Mapa), não afirma nada; com dado e nenhum equipamento, diz isso.
  def equipment_summary(report)
    count_columns = EQUIPMENT_COUNTS.values.flatten + [ "other_terminals_count" ]
    return if report["has_payment_link"].nil? && count_columns.all? { |column| report[column].nil? }

    terminals = EQUIPMENT_COUNTS.filter_map do |name, columns|
      count = columns.sum { |column| report[column].to_i }
      "#{count} #{name}" if count.positive?
    end
    others = report["other_terminals_count"].to_i
    if others.positive?
      terminals << if terminals.any?
        others == 1 ? "+1 outro" : "+#{others} outros"
      else
        others == 1 ? "1 terminal" : "#{others} terminais"
      end
    end

    labels = []
    labels << "Link pgto" if report["has_payment_link"]
    labels.concat(terminals)
    labels.any? ? labels.join(" · ") : "Sem equipamentos"
  end

  def brl(amount)
    # Espaço não separável entre "R$" e o número: o valor nunca quebra em duas linhas.
    number_to_currency(amount.to_d, unit: "R$", separator: ",", delimiter: ".",
      format: "%u\u00A0%n")
  end

  # Mesmo valor, com os centavos em corpo menor. \u00C9 para o card de m\u00E9trica, onde cinco valores
  # dividem a largura da tela e o dos milh\u00F5es n\u00E3o cabia: a compet\u00EAncia fechada de um MIC
  # aparecia como "R$ 2.475.790,\u2026". Nenhum algarismo some nem encolhe \u2014 s\u00F3 a fra\u00E7\u00E3o, que \u00E9 a
  # parte que se l\u00EA por \u00FAltimo. Medido: devolve 15px dos 26 que faltavam.
  # Ver a regra de .metric-value, que tamb\u00E9m deixou de cortar com retic\u00EAncias.
  def brl_metric(amount)
    formatado = brl(amount)
    inteiro, virgula, centavos = formatado.rpartition(",")
    return formatado if virgula.blank?

    safe_join([ inteiro, content_tag(:span, "#{virgula}#{centavos}", class: "metric-value__cents") ])
  end
end
