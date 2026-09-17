require "test_helper"

# Fronteiras do Anexo B, faixa a faixa. Ruby puro, sem banco.
class SubChannelIndicatorRulesTest < ActiveSupport::TestCase
  def verdict(...) = SubChannelIndicatorRules.verdict(...)

  test "qualidade das indicações: menor é melhor, fronteiras de duas casas" do
    assert_equal :adequate, verdict(:quality, 10)
    assert_equal :attention, verdict(:quality, 10.01)
    assert_equal :attention, verdict(:quality, 25)
    assert_equal :risk, verdict(:quality, 25.01)
    # O anexo não tem faixa entre 10% e 10,01%: o percentual é arredondado a duas casas antes
    # de comparar, e 10,004% cai em Adequado enquanto 10,006% cai em Atenção.
    assert_equal :adequate, verdict(:quality, 10.004)
    assert_equal :attention, verdict(:quality, 10.006)
  end

  test "credenciamentos: maior é melhor, em inteiros" do
    assert_equal :adequate, verdict(:accreditations, 10)
    assert_equal :attention, verdict(:accreditations, 9)
    assert_equal :attention, verdict(:accreditations, 5)
    assert_equal :risk, verdict(:accreditations, 4)
    assert_equal :risk, verdict(:accreditations, 0)
  end

  test "volume transacional: maior é melhor" do
    assert_equal :adequate, verdict(:volume, 92)
    assert_equal :attention, verdict(:volume, 91.99)
    assert_equal :attention, verdict(:volume, 88.01)
    assert_equal :risk, verdict(:volume, 88)
  end

  test "descredenciamento e ECs sem transação: menor é melhor" do
    assert_equal :adequate, verdict(:attrition, 2)
    assert_equal :attention, verdict(:attrition, 2.01)
    assert_equal :attention, verdict(:attrition, 5)
    assert_equal :risk, verdict(:attrition, 5.01)

    assert_equal :adequate, verdict(:activity, 5)
    assert_equal :attention, verdict(:activity, 5.01)
    assert_equal :attention, verdict(:activity, 10)
    assert_equal :risk, verdict(:activity, 10.01)
  end

  test "sem valor não há leitura" do
    assert_nil verdict(:volume, nil)
  end
end
