require "test_helper"

# Fronteiras das tabelas do modelo de remuneração. Ruby puro, sem banco.
class SubChannelCompensationRulesTest < ActiveSupport::TestCase
  test "faixas de credenciamento nas fronteiras publicadas" do
    assert_equal 0, SubChannelCompensationRules.accreditation_bracket_value(14_999.99, with_auto: false)
    assert_equal 50, SubChannelCompensationRules.accreditation_bracket_value(15_000.00, with_auto: false)
    assert_equal 250, SubChannelCompensationRules.accreditation_bracket_value(15_000.00, with_auto: true)
    # Leitura literal da tabela ("de" inclusivo); a simulação oficial diverge exatamente
    # neste degrau e a dúvida está registrada no plano para confirmação com a Fiserv.
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
    up = SubChannelCompensationRules.performance_adjustment(previous: 100, current: 250, recurring: 10)
    assert_operator up[:accelerator], :>, 0
    assert_equal 0.0, up[:reducer]

    down = SubChannelCompensationRules.performance_adjustment(previous: 100, current: 40, recurring: 10)
    assert_equal 0.0, down[:accelerator]
    assert_in_delta 10 * 0.20, down[:reducer], 0.0001

    flat = SubChannelCompensationRules.performance_adjustment(previous: 100, current: 110, recurring: 10)
    assert_equal 0.0, flat[:accelerator]
    assert_equal 0.0, flat[:reducer]
  end

  test "sem mês anterior positivo não há base de comparação nem ajuste" do
    result = SubChannelCompensationRules.performance_adjustment(previous: 0, current: 500, recurring: 10)
    assert_nil result[:growth]
    assert_equal 0.0, result[:accelerator]
    assert_equal 0.0, result[:reducer]
  end
end
