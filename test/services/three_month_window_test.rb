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

  # Com o calendário livre, o mês escolhido vale mesmo sem volume importado: a tabela
  # mostra as colunas sem cobertura em vez de trocar a escolha do usuário em silêncio.
  test "mês sem volume importado ainda abre a janela pedida" do
    assert_equal [ Date.new(2019, 1, 1), Date.new(2019, 2, 1), Date.new(2019, 3, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2019-01")
  end

  test "competência ilegível cai na regra padrão em vez de estourar" do
    [ "mês passado", "2026-13", "", nil ].each do |value|
      assert_equal ThreeMonthEarningsQuery.window(PERIODS),
        ThreeMonthEarningsQuery.window(PERIODS, start_period: value), value.inspect
    end
  end

  # O calendário entrega duas datas quaisquer; o que vale é o mês de cada uma.
  test "o mês final escolhido encurta a janela" do
    assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04", end_period: "2026-05")
  end

  # O calendário preenche as duas datas com a mesma no primeiro clique; escolher um dia só
  # abre a janela cheia, em vez de encolher a apuração para aquele mês sem o usuário pedir.
  test "as duas datas no mesmo mês mantêm a janela de três meses" do
    janela = [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ]

    assert_equal janela,
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04-01", end_period: "2026-04-01")
    assert_equal janela,
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04-01", end_period: "2026-04-20")
  end

  # O modelo é dos três primeiros meses: intervalo maior é cortado no M2, não recusado.
  test "intervalo maior que três meses é cortado no M2" do
    assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04", end_period: "2026-12")
  end

  # Fim anterior ao início, ou ilegível, não vira recorte às avessas: cai nos três meses.
  test "fim inválido cai na janela de três meses" do
    [ "2026-03", "não é mês", "", nil ].each do |value|
      assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1), Date.new(2026, 6, 1) ],
        ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04", end_period: value), value.inspect
    end
  end

  # As datas chegam do calendário como dia completo; o dia não muda a apuração, que é mensal.
  test "aceita data completa e usa o mês dela" do
    assert_equal [ Date.new(2026, 4, 1), Date.new(2026, 5, 1) ],
      ThreeMonthEarningsQuery.window(PERIODS, start_period: "2026-04-17", end_period: "2026-05-02")
  end
end
