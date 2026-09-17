require "test_helper"

# Fronteiras das tabelas do modelo de remuneração. Ruby puro, sem banco.
class SubChannelCompensationRulesTest < ActiveSupport::TestCase
  test "faixas de credenciamento nas fronteiras publicadas" do
    assert_equal 0, SubChannelCompensationRules.accreditation_bracket_value(14_999.99, with_auto: false)
    assert_equal 50, SubChannelCompensationRules.accreditation_bracket_value(15_000.00, with_auto: false)
    assert_equal 250, SubChannelCompensationRules.accreditation_bracket_value(15_000.00, with_auto: true)
    # Leitura literal da tabela ("de" inclusivo). As duas simulações do Anexo C discordam
    # entre si neste degrau: a Simulação 1 lê R$ 20.000 na faixa 20.000–24.999,99 (C = 300,
    # a tabela) e a Simulação 2 lê na faixa de baixo (B = 50). A tabela concorda com a
    # primeira, que fecha no centavo no teste abaixo — a Simulação 2 escorrega um degrau.
    assert_equal 55, SubChannelCompensationRules.accreditation_bracket_value(20_000.00, with_auto: false)
    assert_equal 174, SubChannelCompensationRules.accreditation_bracket_value(12_000_000, with_auto: false)
    assert_equal 2_200, SubChannelCompensationRules.accreditation_bracket_value(12_000_000, with_auto: true)
  end

  test "faixas de net MDR, incluindo o buraco entre 0,39% e 0,40% e o piso zerado" do
    assert_nil SubChannelCompensationRules.mdr_rates(nil)
    assert_equal({ debit: 0.0009, credit: 0.0018 }, SubChannelCompensationRules.mdr_rates(0.41))
    # 0,40% exato não é "acima de 0,40%": cai na segunda faixa, fechando o vão do slide.
    assert_equal({ debit: 0.0006, credit: 0.0012 }, SubChannelCompensationRules.mdr_rates(0.40))
    assert_equal({ debit: 0.0006, credit: 0.0012 }, SubChannelCompensationRules.mdr_rates(0.35))
    assert_equal({ debit: 0.0003, credit: 0.0006 }, SubChannelCompensationRules.mdr_rates(0.3499))
    assert_equal({ debit: 0.0001, credit: 0.0002 }, SubChannelCompensationRules.mdr_rates(0.25))
    # Abaixo de 0,25% a regra existe e é zero — não é ausência de faixa.
    assert_equal({ debit: 0.0, credit: 0.0 }, SubChannelCompensationRules.mdr_rates(0.2499))
  end

  test "gabarito oficial de recorrência fecha no centavo" do
    rates = SubChannelCompensationRules.mdr_rates(0.36)
    debit = 261_900 * rates[:debit]
    credit = 320_100 * rates[:credit]
    assert_in_delta 157.14, debit, 0.001
    assert_in_delta 384.12, credit, 0.001
    assert_in_delta 541.26, debit + credit, 0.001
  end

  # Gabarito oficial da Fiserv: meses de 18k/15k/55k pagam R$ 50, nada e R$ 39. A propriedade
  # que ele demonstra — soma da marca d'água igual à faixa do mês de pico — é o que autoriza
  # `audit_accreditation_earnings` a apurar a janela a partir do pico, sem percorrer mês a mês.
  test "gabarito oficial de credenciamento: marca d'água de três meses fecha na faixa do pico" do
    meses = [ 18_000, 15_000, 55_000 ]
    pago = 0

    parcelas = meses.map do |revenue|
      faixa = SubChannelCompensationRules.accreditation_bracket_value(revenue, with_auto: false)
      diferenca = [ faixa - pago, 0 ].max
      pago += diferenca
      diferenca
    end

    assert_equal [ 50, 0, 39 ], parcelas
    assert_equal 89, pago
    assert_equal SubChannelCompensationRules.accreditation_bracket_value(meses.max, with_auto: false),
      pago, "a janela tem que fechar na faixa do mês de pico"
  end

  # Simulação 1 do Anexo C, com antecipação automática: janeiro R$ 20.000 paga R$ 300,
  # fevereiro R$ 75.000 paga R$ 490 e março R$ 250.000 paga R$ 1.410. É o gabarito que
  # exercita a marca d'água nos três meses, com mudança de faixa em cada um — e o que
  # confirma a leitura literal da tabela na fronteira de R$ 20.000.
  test "gabarito oficial de credenciamento com auto/flex fecha nos três meses" do
    meses = [ 20_000, 75_000, 250_000 ]
    pago = 0

    parcelas = meses.map do |revenue|
      faixa = SubChannelCompensationRules.accreditation_bracket_value(revenue, with_auto: true)
      diferenca = [ faixa - pago, 0 ].max
      pago += diferenca
      diferenca
    end

    assert_equal [ 300, 490, 1_410 ], parcelas
    assert_equal 2_200, pago
    assert_equal SubChannelCompensationRules.accreditation_bracket_value(meses.max, with_auto: true),
      pago, "a janela fecha na faixa do mês de pico"
  end

  test "acelerador só a partir de 20% e com a faixa superior em 100% exato" do
    assert_equal 0.0, SubChannelCompensationRules.accelerator_rate(0.1999)
    assert_equal 0.0004, SubChannelCompensationRules.accelerator_rate(0.20)
    assert_equal 0.0005, SubChannelCompensationRules.accelerator_rate(0.30)
    assert_equal 0.0007, SubChannelCompensationRules.accelerator_rate(0.50)
    assert_equal 0.0010, SubChannelCompensationRules.accelerator_rate(1.00)
    assert_equal 0.0010, SubChannelCompensationRules.accelerator_rate(4.20)
  end

  test "redutor por faixa de queda, com a faixa -20/-29,99 corrigida do slide" do
    assert_equal 0.0, SubChannelCompensationRules.reducer_rate(-0.0999)
    assert_equal 0.05, SubChannelCompensationRules.reducer_rate(-0.10)
    assert_equal 0.10, SubChannelCompensationRules.reducer_rate(-0.25)
    assert_equal 0.15, SubChannelCompensationRules.reducer_rate(-0.30)
    assert_equal 0.20, SubChannelCompensationRules.reducer_rate(-0.50)
    assert_equal 0.20, SubChannelCompensationRules.reducer_rate(-1.0)
  end

  test "acelerador e redutor nunca coexistem" do
    up = SubChannelCompensationRules.performance_adjustment(previous: 100, current: 250, participation: 10)
    assert_operator up[:accelerator], :>, 0
    assert_equal 0.0, up[:reducer]

    down = SubChannelCompensationRules.performance_adjustment(previous: 100, current: 40, participation: 10)
    assert_equal 0.0, down[:accelerator]
    assert_in_delta 10 * 0.20, down[:reducer], 0.0001

    flat = SubChannelCompensationRules.performance_adjustment(previous: 100, current: 110, participation: 10)
    assert_equal 0.0, flat[:accelerator]
    assert_equal 0.0, flat[:reducer]
  end

  test "sem mês anterior positivo não há base de comparação nem ajuste" do
    result = SubChannelCompensationRules.performance_adjustment(previous: 0, current: 500, participation: 10)
    assert_nil result[:growth]
    assert_equal 0.0, result[:accelerator]
    assert_equal 0.0, result[:reducer]
  end
end
