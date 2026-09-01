require "test_helper"

# Página 3M de ponta a ponta: import sintético, view de credenciamento e cálculo ao vivo.
# Todos os esperados saem das lojas declaradas no BinWorkbook — nada fixado à mão.
class ThreeMonthEarningsTest < ActiveSupport::TestCase
  PERIODS = [ Date.new(2026, 6, 1), Date.new(2026, 7, 1), Date.new(2026, 8, 1) ].freeze
  MONTHS = %w[202606 202607 202608].freeze

  setup do
    @lojas = BinWorkbook.earnings_lojas
    import_synthetic_workbook(lojas: @lojas)
    refresh_audit_views
    @query = ThreeMonthEarningsQuery.new(periods: PERIODS)
  end

  test "volumes de débito e crédito por sub-canal batem com a planilha" do
    gama = @query.by_sub_channel.find { |row| row[:name] == "MIC GAMA" }
    gama_lojas = @lojas.select { |loja| loja.sub_channel_name == "MIC GAMA" }

    MONTHS.each_with_index do |month, index|
      assert_in_delta gama_lojas.sum { |loja| loja.debito(month) },
        gama[:months][index][:debit], 0.001, "débito de #{month}"
      assert_in_delta gama_lojas.sum { |loja| loja.credito(month) },
        gama[:months][index][:credit], 0.001, "crédito de #{month}"
    end
  end

  test "net MDR ponderado exclui o EC Inativo e o repasse usa a faixa da carteira" do
    gama = @query.by_sub_channel.find { |row| row[:name] == "MIC GAMA" }

    # Só o EC com MDR entra: a média ponderada colapsa no valor dele.
    with_mdr = @lojas.find { |loja| loja.sub_channel_name == "MIC GAMA" && loja.net_mdr.is_a?(Numeric) }
    assert_in_delta with_mdr.net_mdr, gama[:weighted_net_mdr], 0.0001

    rates = SubChannelCompensationRules.mdr_rates(with_mdr.net_mdr)
    expected_recurring = MONTHS.sum do |month|
      debit = @lojas.select { |l| l.sub_channel_name == "MIC GAMA" }.sum { |l| l.debito(month) }
      credit = @lojas.select { |l| l.sub_channel_name == "MIC GAMA" }.sum { |l| l.credito(month) }
      debit * rates[:debit] + credit * rates[:credit]
    end
    assert_in_delta expected_recurring, gama[:recurring_total], 0.001
  end

  test "carteira em crescimento acima de 100% aplica o acelerador sobre o incremento" do
    gama = @query.by_sub_channel.find { |row| row[:name] == "MIC GAMA" }
    totals = MONTHS.map do |month|
      @lojas.select { |l| l.sub_channel_name == "MIC GAMA" }
        .sum { |l| l.debito(month) + l.credito(month) }
    end

    expected = totals.each_cons(2).sum do |previous, current|
      growth = (current - previous).to_f / previous
      growth >= 0.20 ? (current - previous) * SubChannelCompensationRules.accelerator_rate(growth) : 0.0
    end
    assert_operator gama[:accelerator_total], :>, 0
    assert_in_delta expected, gama[:accelerator_total], 0.001
    assert_equal 0.0, gama[:reducer_total]
  end

  test "carteira em queda acima de 50% aplica o redutor sobre o repasse do mês" do
    delta = @query.by_sub_channel.find { |row| row[:name] == "MIC DELTA" }
    delta_loja = @lojas.find { |loja| loja.sub_channel_name == "MIC DELTA" }
    rates = SubChannelCompensationRules.mdr_rates(delta_loja.net_mdr)

    last_total = delta_loja.debito("202608") + delta_loja.credito("202608")
    previous_total = delta_loja.debito("202607") + delta_loja.credito("202607")
    drop = (last_total - previous_total).to_f / previous_total
    last_recurring = delta_loja.debito("202608") * rates[:debit] +
      delta_loja.credito("202608") * rates[:credit]

    assert_operator drop, :<, -0.5
    assert_in_delta last_recurring * SubChannelCompensationRules.reducer_rate(drop),
      delta[:reducer_total], 0.001

    # A exclusividade é por transição, não pela janela: a primeira transição da DELTA
    # cresce 100% e gera acelerador, a segunda cai e gera redutor — os dois convivem
    # na mesma janela, cada um no seu mês.
    first_growth_increment = (delta_loja.debito("202607") + delta_loja.credito("202607")) -
      (delta_loja.debito("202606") + delta_loja.credito("202606"))
    growth = first_growth_increment.to_f /
      (delta_loja.debito("202606") + delta_loja.credito("202606"))
    assert_in_delta first_growth_increment * SubChannelCompensationRules.accelerator_rate(growth),
      delta[:accelerator_total], 0.001
  end

  test "credenciamento em janela parcialmente coberta apura a marca d'água e expõe os meses" do
    gama_ec = @lojas.find { |loja| loja.ec == "50000001" }
    row = ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings WHERE establishment_id = " \
      "(SELECT id FROM establishments WHERE ec = '50000001')"
    ).to_a.sole

    # M0 (julho, fechado) e M1 (agosto, aberto até o corte) contam; M2 (setembro) não tem
    # cobertura e fica de fora — dois meses apurados, não três.
    assert_equal 2, row["months_observed"]
    peak = [ gama_ec.total_m1, gama_ec.total_atual ].max
    assert_in_delta peak, row["peak_month_revenue"].to_f, 0.001
    assert_in_delta SubChannelCompensationRules.accreditation_bracket_value(peak, with_auto: false),
      row["addon_without_auto"].to_f, 0.001
    assert_in_delta SubChannelCompensationRules.accreditation_bracket_value(peak, with_auto: true),
      row["addon_with_auto"].to_f, 0.001
    # App acessado e M0 dentro da apuração: digitalização entra, uma única vez.
    assert_in_delta SubChannelCompensationRules::DIGITALIZATION_FEE,
      row["digitalization_amount"].to_f, 0.001
    assert_equal true, row["auto_classified"]
  end

  test "credenciamento fora do histórico não vira ganho zero: zero meses apurados" do
    row = ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings WHERE establishment_id = " \
      "(SELECT id FROM establishments WHERE ec = '50000003')"
    ).to_a.sole

    assert_equal 0, row["months_observed"]
    assert_nil row["peak_month_revenue"]
    assert_equal 0, row["addon_without_auto"].to_f
    assert_equal 0, row["digitalization_amount"].to_f
  end

  test "nível 2 entrega cards por estabelecimento com o credenciamento anexado" do
    sub_channel = SubChannel.find_by!(name: "MIC GAMA")
    rows = ThreeMonthEarningsQuery.new(periods: PERIODS).by_establishment(sub_channel_id: sub_channel.id)

    assert_equal @lojas.count { |loja| loja.sub_channel_name == "MIC GAMA" }, rows.size
    with_accreditation = rows.find { |row| row[:ec] == "50000001" }
    assert_equal 2, with_accreditation[:accreditation]["months_observed"]
  end

  test "sem volume mensal importado a consulta responde vazia, sem erro" do
    ApplicationRecord.connection.execute("DELETE FROM monthly_volumes_consolidated")
    assert_equal [], ThreeMonthEarningsQuery.new(periods: PERIODS).by_sub_channel
    assert_equal [], ThreeMonthEarningsQuery.available_periods
  end
end
