require "test_helper"

# Série mensal do ganho recorrente: esperados recomputados das lojas sintéticas, mês a
# mês — cada competência com o próprio MDR, a própria faixa e o próprio repasse.
class RecurringEarningsTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

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
        base = current[:recurring] + current[:accreditation]
        expected = base * SubChannelCompensationRules.reducer_rate(growth)
        assert_in_delta expected, current[:reducer], 0.001, "redutor em #{current[:period]}"
        assert_equal 0.0, current[:accelerator]
      end
    end
  end

  # Anexo C, 1.1.3: o redutor incide sobre a Participação do Franqueado, não só sobre a linha
  # recorrente. Com a janela do EC dentro da série, a parcela do credenciamento cai no mesmo
  # mês da queda e tem de entrar na base — é a diferença entre esta regra e a anterior.
  test "o redutor incide sobre a recorrência mais a parcela do credenciamento" do
    delta_ec = Establishment.find_by!(ec: "50000003")
    # Janela do EC trazida para jun/jul/ago, e o volume de agosto elevado acima do piso das
    # faixas: assim a parcela de M2 cai exatamente no mês em que a carteira DELTA despenca.
    # Sem isso a parcela seria zero — as faixas começam em R$ 15.000 — e o teste não provaria
    # nada. Mexe só no volume 'total' (base da faixa), não em débito/crédito, para a queda da
    # série recorrente continuar sendo a mesma.
    ApplicationRecord.connection.execute(
      "UPDATE map_snapshots SET accredited_on = DATE '2026-06-10' " \
      "WHERE establishment_id = #{delta_ec.id}"
    )
    ApplicationRecord.connection.execute(
      "UPDATE monthly_volumes_consolidated SET amount = 55000 " \
      "WHERE establishment_id = #{delta_ec.id} AND metric = 'total' AND period = DATE '2026-08-01'"
    )
    refresh_audit_views
    delta = RecurringEarningsQuery.new.by_sub_channel.find { |row| row[:name] == "MIC DELTA" }

    com_parcela = delta[:months].select { |month| month[:accreditation].positive? }
    assert_predicate com_parcela, :any?, "a janela do EC tem de cruzar a série, senão o teste é vácuo"

    em_queda = delta[:months].each_cons(2).find do |previous, current|
      current[:total] < previous[:total] && current[:accreditation].positive?
    end
    assert em_queda, "o fixture precisa de um mês com queda e parcela ao mesmo tempo"

    previous, current = em_queda
    growth = (current[:total] - previous[:total]) / previous[:total]
    base = current[:recurring] + current[:accreditation]

    assert_in_delta base * SubChannelCompensationRules.reducer_rate(growth),
      current[:reducer], 0.001
    assert_operator current[:reducer], :>,
      current[:recurring] * SubChannelCompensationRules.reducer_rate(growth),
      "com a parcela na base, o redutor é maior do que era pela regra antiga"
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

  # A série só muda numa consolidação; até lá a resposta vem do cache, e o carimbo da
  # última consolidação na chave invalida sozinho — tanto no lote novo quanto no
  # reprocessamento de um lote já validado, que não cria id novo.
  test "a série fica em cache até a próxima consolidação" do
    # Devolve o mesmo objeto no fim: o rate_limit do controller prende o store na
    # definição da classe, e um NullStore novo deixaria aquele teste sem simulação.
    original_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    query = RecurringEarningsQuery.new
    assert_equal @reports, query.by_sub_channel

    # Só a consulta que monta a chave (carimbo da última consolidação).
    cached = assert_queries_count(1) { query.by_sub_channel }
    assert_equal @reports, cached

    Operations::ReprocessBatch.call(ImportBatch.validated.last)
    assert_queries_match(/monthly_volumes_consolidated/) { RecurringEarningsQuery.new.by_sub_channel }
    assert_queries_count(1) { RecurringEarningsQuery.new.by_sub_channel }

    @lojas.first.dias_atual = @lojas.first.dias_atual.merge(1 => 999)
    import_synthetic_workbook(lojas: @lojas, filename: "BIN_TESTE_20260818.xlsx")
    assert_queries_match(/monthly_volumes_consolidated/) { RecurringEarningsQuery.new.by_sub_channel }
  ensure
    Rails.cache = original_store
  end
end
