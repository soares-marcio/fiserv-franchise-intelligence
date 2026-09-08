require "test_helper"

# A grade do calendário, sem banco. Agosto de 2026 é o mês do exercício porque começa num
# sábado: a primeira linha tem seis dias de julho e um só da competência, que é justamente o
# caso que a tabela de "semanas de 7 dias" apresentava como desempenho ruim.
class RevenueCalendarTest < ActiveSupport::TestCase
  AGOSTO = Date.new(2026, 8, 1)

  test "a grade começa no domingo e a primeira linha traz só o dia 1" do
    semanas = build.weeks

    primeira = semanas.first
    assert_equal Date.new(2026, 7, 26), primeira.cells.first.date, "a linha abre no domingo"
    assert_equal 6, primeira.cells.count(&:outside?)
    assert_equal [ 1 ], primeira.cells.reject(&:outside?).map(&:day)
    assert_equal "dia 1", primeira.label
  end

  test "o rótulo diz a faixa de dias que a semana cobre na competência" do
    assert_equal [ "dia 1", "2–8", "9–15", "16–22", "23–29", "30–31" ], build.weeks.map(&:label)
  end

  # A distinção que a tela inteira existe para não perder: o arquivo cobre até o dia 2, então
  # do 3 em diante não é "não vendeu", é "não sabemos".
  test "dia além da cobertura é sem dado, e dia coberto sem venda é zero" do
    calendario = build(covered_days: 2, days: [ { "day" => 1, "revenue" => "500.0", "establishments" => 3 } ])
    celulas = calendario.weeks.flat_map(&:cells).reject(&:outside?).index_by(&:day)

    assert_equal 500.to_d, celulas[1].revenue
    assert_equal :covered, celulas[2].state, "dia coberto sem linha na consulta é zero, não lacuna"
    assert_equal 0.to_d, celulas[2].revenue
    assert_predicate celulas[3], :uncovered?
    assert_predicate celulas[31], :uncovered?
  end

  test "a escala de intensidade toma o maior dia do próprio mês" do
    calendario = build(days: [
      { "day" => 1, "revenue" => "100.0", "establishments" => 1 },
      { "day" => 2, "revenue" => "900.0", "establishments" => 2 }
    ])

    assert_equal 900.to_d, calendario.max_revenue
  end

  test "sem dia nenhum com valor, a escala não divide por zero" do
    assert_equal 0, build(days: []).max_revenue
  end

  private

  def build(covered_days: 31, days: nil, weeks: [])
    days ||= (1..covered_days).map { |day| { "day" => day, "revenue" => "0.0", "establishments" => 0 } }
    RevenueCalendar.new(period: AGOSTO, covered_days:, days:, weeks:)
  end
end
