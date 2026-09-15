class EstablishmentRevenuePage
  include Enumerable

  attr_reader :rows, :total_count, :totals, :page, :per_page, :variation_counts, :status_counts,
    :overall_totals, :low_revenue_counts

  def initialize(rows:, total_count:, totals:, page:, per_page:, variation_counts: {},
    status_counts: {}, overall_totals: nil, low_revenue_counts: {})
    @rows = rows
    @total_count = total_count.to_i
    @totals = totals
    @page = page
    @per_page = per_page
    @variation_counts = variation_counts
    @status_counts = status_counts
    @overall_totals = overall_totals
    # Quantos clientes do recorte ficaram abaixo do corte em cada competência. Duas contagens
    # independentes: o mesmo cliente pode estar nas duas, e a soma delas não descreve nada.
    @low_revenue_counts = low_revenue_counts
  end

  def each(&block)
    rows.each(&block)
  end

  # Ticket médio da carteira: o mês anterior cheio dividido pelos CNPJs ativos do recorte.
  # Mistura o mês fechado com o status de hoje por decisão do usuário — a leitura é "quanto
  # rende cada cliente ativo" —, e por isso a tela escreve o divisor ao lado do valor. Sem
  # CNPJ ativo não há média: devolve nil em vez de zero, que seria outra afirmação.
  def average_ticket
    ativos = status_counts["Active"].to_i
    return if ativos.zero?

    totals[:previous_full_revenue] / ativos
  end

  def total_pages
    return 1 if total_count < 1 || per_page.to_i < 1

    (total_count.to_f / per_page).ceil
  end
end
