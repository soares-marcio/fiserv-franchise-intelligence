require "test_helper"

# A janela decide o que a tela compara: qual competência está aberta e qual faixa de dias
# vale nos dois meses. Comparar faixas diferentes inventaria variação que não existe.
class PeriodWindowTest < ActiveSupport::TestCase
  ABERTA = { "period" => "2026-09-01", "max_known_day" => 12, "closed" => false }.freeze
  FECHADA = { "period" => "2026-08-01", "max_known_day" => 31, "closed" => true }.freeze

  test "sem cobertura nenhuma não há janela" do
    assert_nil PeriodWindow.from_coverages([])
  end

  test "sem competência pedida, a janela é a do mês aberto" do
    window = PeriodWindow.from_coverages([ FECHADA, ABERTA ])

    assert_equal Date.new(2026, 9, 1), window.current_period
    assert_equal Date.new(2026, 8, 1), window.previous_period
  end

  test "com todas as competências fechadas, a janela é a primeira da lista" do
    window = PeriodWindow.from_coverages([ FECHADA ])

    assert_equal Date.new(2026, 8, 1), window.current_period
  end

  test "a competência pedida vence a regra do mês aberto" do
    window = PeriodWindow.from_coverages([ FECHADA, ABERTA ], period: "2026-08-01")

    assert_equal Date.new(2026, 8, 1), window.current_period
  end

  test "competência pedida em qualquer dia do mês resolve para a competência" do
    window = PeriodWindow.from_coverages([ FECHADA, ABERTA ], period: "2026-08-17")

    assert_equal Date.new(2026, 8, 1), window.current_period
  end

  test "competência ilegível cai na regra padrão em vez de estourar" do
    window = PeriodWindow.from_coverages([ FECHADA, ABERTA ], period: "mês passado")

    assert_equal Date.new(2026, 9, 1), window.current_period
  end

  test "competência inexistente na cobertura cai na regra padrão" do
    window = PeriodWindow.from_coverages([ FECHADA, ABERTA ], period: "2020-01-01")

    assert_equal Date.new(2026, 9, 1), window.current_period
  end

  # O corte observado é o último dia com movimento; sem dias informados a janela abriria
  # vazia e a tela mostraria zero faturamento em vez do mês inteiro.
  test "sem dias informados a janela vai do dia 1 ao corte conhecido" do
    window = PeriodWindow.from_coverages([ ABERTA ])

    assert_equal 1, window.from_day
    assert_equal 12, window.to_day
    assert_equal 12, window.max_day
  end

  test "cobertura sem corte conhecido abre o mês inteiro" do
    window = PeriodWindow.from_coverages([ ABERTA.merge("max_known_day" => 0) ])

    assert_equal 31, window.max_day
    assert_equal 31, window.to_day
  end

  test "dias fora do calendário caem no padrão" do
    window = PeriodWindow.from_coverages([ ABERTA ], from_day: 0, to_day: 40)

    assert_equal 1, window.from_day
    assert_equal 12, window.to_day
  end

  test "faixa invertida vira um dia só, nunca uma faixa negativa" do
    window = PeriodWindow.from_coverages([ ABERTA ], from_day: 9, to_day: 3)

    assert_equal 9, window.from_day
    assert_equal 9, window.to_day
  end

  test "as amarras da consulta levam as três competências e a faixa" do
    window = PeriodWindow.from_coverages([ ABERTA ], from_day: 2, to_day: 5)

    assert_equal({ current_period: Date.new(2026, 9, 1), previous_period: Date.new(2026, 8, 1),
      penultimate_period: Date.new(2026, 7, 1), from_day: 2, to_day: 5 }, window.to_binds)
  end

  # O modal mostra três competências, mas a mais antiga não vem do arquivo atual: ela existe
  # se importações anteriores a cobriram. Sem cobertura, coluna zerada diria "sem venda"
  # onde a verdade é "sem dado".
  test "a penúltima competência vira coluna quando tem cobertura" do
    julho = { "period" => "2026-07-01", "max_known_day" => 31, "closed" => true }
    window = PeriodWindow.from_coverages([ julho, FECHADA, ABERTA ])

    assert_equal [ Date.new(2026, 7, 1), Date.new(2026, 8, 1), Date.new(2026, 9, 1) ],
      window.daily_columns.keys
    assert_equal %w[penultimate_amount previous_amount current_amount],
      window.daily_columns.values
  end

  test "sem cobertura da penúltima, o modal fica com as duas competências do arquivo" do
    window = PeriodWindow.from_coverages([ FECHADA, ABERTA ])

    assert_equal [ Date.new(2026, 8, 1), Date.new(2026, 9, 1) ], window.daily_columns.keys
  end
end
