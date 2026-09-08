require "test_helper"

# Regra da ordenação das listagens, sem banco: o que vem da URL é validado contra a lista
# fechada da tela, e o resto da aplicação só conversa com o resultado.
class ListingSortTest < ActiveSupport::TestCase
  COLUMNS = {
    "previous_full_revenue" => "Mês anterior cheio",
    "current_revenue" => "Mês atual"
  }.freeze

  test "sem escolha, vale a coluna padrão do maior para o menor" do
    sort = build

    assert_equal [ "previous_full_revenue", "desc" ], [ sort.column, sort.direction ]
    assert sort.default?
    assert_equal({ sort: nil, direction: nil }, sort.params)
  end

  # Link velho e URL editada à mão não podem quebrar a tela — nem virar SQL.
  test "coluna fora da lista e sentido inválido caem no padrão" do
    [ "cnpj", "current_revenue; DROP TABLE", "", nil ].each do |column|
      assert_equal "previous_full_revenue", build(column:).column, column.inspect
    end

    assert_equal "desc", build(column: "current_revenue", direction: "ao contrário").direction
  end

  test "a coluna escolhida sai nos parâmetros e a ordem padrão não" do
    escolhida = build(column: "current_revenue", direction: "asc")

    assert_not escolhida.default?
    assert_equal({ sort: "current_revenue", direction: "asc" }, escolhida.params)
    assert_equal "Ordenado por Mês atual, do menor para o maior", escolhida.sentence
  end

  test "o próximo clique inverte só na coluna ativa" do
    sort = build(column: "current_revenue", direction: "desc")

    assert_equal "asc", sort.next_direction_for("current_revenue")
    assert_equal "desc", sort.next_direction_for("previous_full_revenue")
    assert_equal [ "descending", "none" ],
      [ sort.aria_for("current_revenue"), sort.aria_for("previous_full_revenue") ]
  end

  test "a ordem em SQL leva o desempate junto" do
    assert_equal "current_revenue DESC NULLS LAST, ec, id",
      build(column: "current_revenue").sql_order_by(tiebreak: "ec, id")
  end

  test "listagem que já está na memória ordena em Ruby, nos dois sentidos" do
    rows = [
      { "current_revenue" => 10 }, { "current_revenue" => 300 }, { "current_revenue" => 0 }
    ]

    assert_equal [ 300, 10, 0 ],
      build(column: "current_revenue").sort_rows(rows).map { |row| row["current_revenue"] }
    assert_equal [ 0, 10, 300 ],
      build(column: "current_revenue", direction: "asc").sort_rows(rows).map { |row| row["current_revenue"] }
  end

  # Variação sem base comparável não tem percentual: o extrator devolve nil. Sem tratamento
  # isso viraria zero e a linha apareceria entre quem caiu e quem cresceu.
  test "linha sem valor fica no fim nos dois sentidos" do
    rows = [ { "v" => 10 }, { "v" => nil }, { "v" => 300 } ]
    colunas = { "v" => "Variação" }

    desc = ListingSort.new(columns: colunas, default: "v", column: "v")
    asc = ListingSort.new(columns: colunas, default: "v", column: "v", direction: "asc")

    assert_equal [ 300, 10, nil ], desc.sort_rows(rows).map { |row| row["v"] }
    assert_equal [ 10, 300, nil ], asc.sort_rows(rows).map { |row| row["v"] }
  end

  # As telas de ganho montam hashes aninhados: o valor não está sob a chave da coluna.
  test "linha com valor aninhado ordena pelo extrator que a tela informa" do
    rows = [ { prize: { total: 5 } }, { prize: { total: 90 } } ]

    ordenadas = build(column: "current_revenue").sort_rows(rows) { |row| row[:prize][:total] }

    assert_equal [ 90, 5 ], ordenadas.map { |row| row[:prize][:total] }
  end

  # Nem toda coluna é dinheiro: a tela do recorrente ordena por nome do subcanal. Sem
  # tratar texto, "MIC GAMA".to_d viraria zero e a ordenação não faria nada.
  test "coluna de texto ordena alfabeticamente, ignorando maiúsculas" do
    rows = [ { "nome" => "MIC GAMA" }, { "nome" => "mic alfa" }, { "nome" => "MIC BETA" } ]
    sort = ListingSort.new(columns: { "nome" => "Subcanal" }, default: "nome",
      column: "nome", direction: "asc")

    assert_equal [ "mic alfa", "MIC BETA", "MIC GAMA" ],
      sort.sort_rows(rows).map { |row| row["nome"] }
  end

  private

  def build(column: nil, direction: nil)
    ListingSort.new(columns: COLUMNS, default: "previous_full_revenue", column:, direction:)
  end
end
