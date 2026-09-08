# Ordenação de uma listagem, num lugar só: valida o que veio da URL contra a lista fechada
# da tela e responde o que a tela e a consulta precisam saber.
#
# A lista é fechada por dois motivos. Na listagem paginada o nome da coluna vira SQL, então
# aceitar qualquer valor seria injeção. E, em qualquer tela, coluna que não existe tem que
# cair no padrão — não em erro: link velho e URL editada à mão não podem quebrar a página.
#
# O que NÃO vive aqui é o mecanismo: quem tem paginação ordena no banco (`sql_order_by`),
# porque ordenar só a página visível daria uma lista errada; quem já traz o array inteiro na
# memória ordena em Ruby (`sort_rows`). Esconder essa diferença atrás de uma abstração só
# mentiria sobre o que acontece.
class ListingSort
  DIRECTIONS = %w[desc asc].freeze

  attr_reader :columns, :column, :direction

  # columns: { "coluna" => "Rótulo na tela" }, na ordem em que aparecem.
  def initialize(columns:, default:, column: nil, direction: nil, default_direction: "desc")
    @columns = columns
    @default = default
    @default_direction = default_direction
    @column = column.to_s.presence_in(columns.keys) || default
    @direction = direction.to_s.presence_in(DIRECTIONS) || default_direction
  end

  def label
    columns[column]
  end

  # A ordem padrão é o estado natural da tela: não vai na URL nem oferece "voltar para ela".
  def default?
    column == @default && direction == @default_direction
  end

  # Primeiro clique numa coluna traz o maior valor no topo — é o que se procura numa
  # auditoria de faturamento; o clique seguinte, na mesma coluna, inverte.
  def next_direction_for(other)
    other == column && direction == "desc" ? "asc" : "desc"
  end

  def aria_for(other)
    return "none" unless other == column

    direction == "desc" ? "descending" : "ascending"
  end

  def active?(other)
    other == column
  end

  def sentence
    return unless label

    "Ordenado por #{label}, #{direction == 'desc' ? 'do maior para o menor' : 'do menor para o maior'}"
  end

  # Parâmetros a levar nos links da tela. Vazio na ordem padrão, para o link ficar limpo.
  def params
    return { sort: nil, direction: nil } if default?

    { sort: column, direction: }
  end

  # Desempate obrigatório: sem ele, linhas de mesmo valor trocam de página entre consultas.
  def sql_order_by(tiebreak:)
    "#{column} #{direction.upcase} NULLS LAST, #{tiebreak}"
  end

  # Listagem que já vem inteira na memória. O extrator existe porque nem toda linha guarda o
  # valor sob a chave da coluna — as telas de ganho montam hashes aninhados.
  def sort_rows(rows, &extractor)
    extractor ||= ->(row) { row[column] || row[column.to_sym] }
    ordenadas = rows.sort_by { |row| extractor.call(row).to_d }
    direction == "desc" ? ordenadas.reverse : ordenadas
  end
end
