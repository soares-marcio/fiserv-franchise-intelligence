require "test_helper"

# Série mensal do ganho recorrente: esperados recomputados das lojas sintéticas, mês a
# mês — cada competência com o próprio MDR, a própria faixa e o próprio repasse.
class RecurringEarningsTest < ActiveSupport::TestCase
  setup do
    @lojas = BinWorkbook.earnings_lojas
    import_synthetic_workbook(lojas: @lojas)
    refresh_audit_views
    @reports = RecurringEarningsQuery.new.by_sub_channel
  end

  test "uma linha por competência, com débito e crédito da planilha" do
    gama = @reports.find { |row| row[:name] == "MIC GAMA" }
    gama_lojas = @lojas.select { |loja| loja.sub_channel_name == "MIC GAMA" }

    assert_equal BinImport::Template::DEFAULT_VOLUME_MONTHS.size, gama[:months].size
    gama[:months].each do |month|
      key = month[:period].strftime("%Y%m")
      assert_in_delta gama_lojas.sum { |loja| loja.debito(key) }, month[:debit], 0.001, "débito de #{key}"
      assert_in_delta gama_lojas.sum { |loja| loja.credito(key) }, month[:credit], 0.001, "crédito de #{key}"
    end
  end

  test "o repasse de cada mês usa a faixa do próprio mês, nunca o montante somado" do
    gama = @reports.find { |row| row[:name] == "MIC GAMA" }
    with_mdr = @lojas.find { |loja| loja.sub_channel_name == "MIC GAMA" && loja.net_mdr.is_a?(Numeric) }
    rates = SubChannelCompensationRules.mdr_rates(with_mdr.net_mdr)

    gama[:months].each do |month|
      expected = month[:debit] * rates[:debit] + month[:credit] * rates[:credit]
      assert_in_delta expected, month[:recurring], 0.001, "repasse de #{month[:period]}"
    end
    # A soma da série é a soma dos meses — nada é reapurado sobre o acumulado.
    assert_in_delta gama[:months].sum { |m| m[:recurring] }, gama[:recurring_total], 0.001
  end

  test "acelerador e redutor seguem as transições da série, nunca juntos no mesmo mês" do
    delta = @reports.find { |row| row[:name] == "MIC DELTA" }

    delta[:months].each_cons(2) do |previous, current|
      growth = (current[:total] - previous[:total]) / previous[:total]
      if growth >= 0.20
        assert_operator current[:accelerator], :>, 0, "acelerador em #{current[:period]}"
        assert_equal 0.0, current[:reducer]
      elsif growth.negative?
        expected = current[:recurring] * SubChannelCompensationRules.reducer_rate(growth)
        assert_in_delta expected, current[:reducer], 0.001, "redutor em #{current[:period]}"
        assert_equal 0.0, current[:accelerator]
      end
    end
  end

  test "primeiro mês da série não tem base de comparação nem ajuste" do
    @reports.each do |report|
      first = report[:months].first
      assert_nil first[:growth]
      assert_equal 0.0, first[:accelerator]
      assert_equal 0.0, first[:reducer]
    end
  end

  test "competências anteriores ao primeiro arquivo ficam marcadas como fallback de MDR" do
    gama = @reports.find { |row| row[:name] == "MIC GAMA" }
    # O lote sintético tem current_period = agosto: todo mês anterior usa o fallback.
    fallback_months, era_months = gama[:months].partition { |m| m[:mdr_fallback] }
    assert_equal [ Date.new(2026, 8, 1) ], era_months.map { |m| m[:period] }
    assert_equal 4, fallback_months.size
  end

  test "EC com MDR Inativo fica fora da média ponderada do mês" do
    gama = @reports.find { |row| row[:name] == "MIC GAMA" }
    with_mdr = @lojas.find { |loja| loja.sub_channel_name == "MIC GAMA" && loja.net_mdr.is_a?(Numeric) }

    gama[:months].each do |month|
      assert_in_delta with_mdr.net_mdr, month[:net_mdr], 0.0001, "MDR de #{month[:period]}"
    end
  end

  test "mês aberto aparece como parcial" do
    gama = @reports.find { |row| row[:name] == "MIC GAMA" }
    partials = gama[:months].select { |m| m[:partial] }.map { |m| m[:period] }
    assert_equal [ Date.new(2026, 8, 1) ], partials
  end
end
