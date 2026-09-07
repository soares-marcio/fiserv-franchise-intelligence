require "test_helper"

# A janela da página 3M: o mês escolhido é o M0 (mês de credenciamento) e os outros dois
# avançam a partir dele. Regra pura, sem banco — a lista de competências vem pronta.
class ThreeMonthWindowTest < ActiveSupport::TestCase
  # Como o seletor entrega: da mais recente para a mais antiga.
  PERIODS = [ Date.new(2026, 8, 1), Date.new(2026, 7, 1), Date.new(2026, 6, 1),
    Date.new(2026, 5, 1), Date.new(2026, 4, 1) ].freeze

  test "sem competência importada não há janela" do
    assert_nil ThreeMonthEarningsQuery.window([])
  end

  # Abrir no mês mais recente mostraria M1 e M2 vazios; a escolha é o M0 mais novo cuja
  # janela inteira já tem volume importado.
  test "sem escolha, abre no M0 mais recente com os três meses disponíveis" do
    assert_equal [ Date.new(2026, 6, 1), Date.new(2026, 7, 1), Date.new(2026, 8, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS)
  end

  test "com menos de três competências, abre na mais recente mesmo incompleta" do
    periods = [ Date.new(2026, 8, 1), Date.new(2026, 7, 1) ]

    assert_equal [ Date.new(2026, 8, 1), Date.new(2026, 9, 1), Date.new(2026, 10, 1) ],
      ThreeMonthEarningsQuery.window(periods)
  end

  test "a competência escolhida vira o M0" do
    assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04")
  end

  test "competência fora da lista importada é ignorada" do
    assert_equal ThreeMonthEarningsQuery.window(PERIODS),
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2019-01")
  end

  test "competência ilegível cai na regra padrão em vez de estourar" do
    [ "mês passado", "2026-13", "", nil ].each do |value|
      assert_equal ThreeMonthEarningsQuery.window(PERIODS),
        ThreeMonthEarningsQuery.window(PERIODS, start_period: value), value.inspect
    end
  end

  # O segundo seletor da tela só oferece os dois meses seguintes ao M0; escolher o
  # primeiro deles fecha a janela em dois meses.
  test "o mês final escolhido encurta a janela" do
    assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04", end_period: "2026-05")
  end

  test "o segundo mês seguinte mantém a janela cheia" do
    assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04", end_period: "2026-06")
  end

  # Fora dos dois meses seguintes — antes do M0, no próprio M0 ou além do M2 — a janela
  # volta ao padrão de três meses em vez de virar um recorte que a tela não oferece.
  test "mês final fora do alcance cai na janela de três meses" do
    [ "2026-03", "2026-04", "2026-07", "não é mês", "", nil ].each do |value|
      assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ],
        ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04", end_period: value), value.inspect
    end
  end
end
