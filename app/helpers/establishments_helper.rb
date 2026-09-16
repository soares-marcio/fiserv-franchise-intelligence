module EstablishmentsHelper
  CONTRACT_STATUSES = %w[Active Suspended].freeze

  # Rótulos dos campos do cadastro que podem divergir entre os ECs do mesmo CNPJ.
  CLIENT_FIELD_LABELS = {
    street_address: "endereço", city: "cidade", state: "UF", cep: "CEP",
    cnae_code: "CNAE", presumed_segment: "segmento presumido", legal_name: "razão social"
  }.freeze

  def client_field_label(field) = CLIENT_FIELD_LABELS.fetch(field, field.to_s)

  # Status do cliente pela regra da casa: a suspensão é do cliente, não do produto. Basta um
  # EC ativo para o cliente estar ativo; suspenso só quando todos os ECs estão suspensos.
  def client_contract_status(establishments)
    statuses = establishments.filter_map { |e| e.current_map_snapshot&.contract_status }
    return if statuses.empty?

    statuses.include?("Active") ? "Active" : statuses.first
  end
  CONTRACT_STATUS_PRESENTATION = {
    "Active" => { label: "Ativo", tone: "success" },
    "Suspended" => { label: "Suspenso", tone: "warning" }
  }.freeze
  # As bases do filtro de faturamento, com o rótulo que a tela mostra. "Todas" é o estado
  # desligado, e por isso vai com valor vazio: o formulário envia o campo sempre.
  REVENUE_BASIS_OPTIONS = [
    [ "Todas", "" ], [ "Mês atual", "atual" ], [ "Mês anterior cheio", "anterior" ]
  ].freeze
  REVENUE_BASIS_LABELS = { "atual" => "Mês atual", "anterior" => "Mês anterior cheio" }.freeze

  # O recorte por extenso, no gatilho da pílula. É o texto mais longo da barra, então vai
  # compacto: sem centavos (o passo do slider é de R$ 1.000 — os centavos são sempre zero e
  # não informam nada) e com um traço no lugar do segundo "R$". Por extenso e com centavos,
  # medido, são 396px de texto para uma caixa de 301px: o teto sumia nas reticências.
  #
  # O revenue_filter_controller.js repete esta regra para reescrever o texto enquanto a alça
  # anda. Mudou aqui, muda lá — senão o rótulo troca de forma quando o JavaScript carrega.
  def revenue_summary(basis, min, max)
    return "qualquer" if basis.blank?

    rotulo = REVENUE_BASIS_LABELS.fetch(basis).downcase
    teto = max || EstablishmentListingQuery::LOW_REVENUE_THRESHOLD
    return "#{rotulo} · até #{brl_round(teto)}" unless min.to_i.positive?

    "#{rotulo} · #{brl_round(min)}–#{number_with_delimiter(teto, delimiter: ".")}"
  end

  # Valor redondo, sem centavos: só no resumo da pílula, onde a largura manda. O espaço não
  # separável é o mesmo do brl, para o valor nunca quebrar em duas linhas.
  def brl_round(amount)
    number_to_currency(amount.to_d, unit: "R$", separator: ",", delimiter: ".",
      precision: 0, format: "%u %n")
  end


  # As duas pontas por extenso, no painel, onde há largura para as duas. O gatilho mostra a
  # versão compacta; aqui vale a precisão, porque é o número que o filtro vai aplicar.
  def revenue_range_label(min, max)
    "#{brl(min || 0)} a #{brl(max || EstablishmentListingQuery::LOW_REVENUE_THRESHOLD)}"
  end

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
