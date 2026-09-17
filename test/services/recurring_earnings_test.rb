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

  # Competência aberta fica de fora: um mês pela metade parece queda por não ter terminado, e
  # o contrato compara mês contra mês, não mês contra meio mês.
  test "acelerador e redutor seguem as transições da série, nunca juntos no mesmo mês" do
    delta = @reports.find { |row| row[:name] == "MIC DELTA" }
    comparadas = 0

    delta[:months].each_cons(2) do |previous, current|
      next if current[:partial]

      comparadas += 1
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

    assert_operator comparadas, :>, 0, "sem transição fechada o teste passaria por vacuidade"
  end

  test "competência aberta não recebe acelerador nem redutor" do
    abertas = @reports.flat_map { |row| row[:months] }.select { |month| month[:partial] }

    assert_predicate abertas, :any?, "o fixture precisa de uma competência aberta"
    abertas.each do |month|
      assert_equal 0.0, month[:accelerator], "acelerador em #{month[:period]}"
      assert_equal 0.0, month[:reducer], "redutor em #{month[:period]}"
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
    # A queda da DELTA está em agosto, que o fixture entrega aberta — e competência aberta
    # não recebe ajuste. Fechar a competência é o que põe o redutor em jogo.
    ApplicationRecord.connection.execute(
      "UPDATE period_coverages SET closed = true WHERE period = DATE '2026-08-01'"
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

  # "Mês contra mês" é competência de calendário. Com um buraco na série, comparar a linha
  # anterior faria agosto medir-se contra junho e inventar uma variação que não existe. Hoje
  # nenhuma série da base real tem buraco (medido: 0 saltos em 58 comparações) — isto é
  # prevenção, e é a razão de o teste construir o buraco à mão.
  test "competência sem a anterior de calendário fica sem base de comparação" do
    delta_ec = Establishment.find_by!(ec: "50000003")
    ApplicationRecord.connection.execute(
      "DELETE FROM monthly_volumes_consolidated " \
      "WHERE establishment_id = #{delta_ec.id} AND period = DATE '2026-07-01'"
    )
    ApplicationRecord.connection.execute(
      "UPDATE period_coverages SET closed = true WHERE period = DATE '2026-08-01'"
    )
    refresh_audit_views

    delta = RecurringEarningsQuery.new.by_sub_channel.find { |row| row[:name] == "MIC DELTA" }
    agosto = delta[:months].find { |month| month[:period] == Date.new(2026, 8, 1) }

    assert_not_includes delta[:months].map { |m| m[:period] }, Date.new(2026, 7, 1),
      "o buraco precisa existir, senão o teste é vácuo"
    assert_nil agosto[:growth], "sem julho, agosto não tem contra o que comparar"
    assert_equal 0.0, agosto[:accelerator]
    assert_equal 0.0, agosto[:reducer]
  end

  test "primeiro mês da série não tem base de comparação nem ajuste" do
    @reports.each do |report|
      first = report[:months].first
      assert_nil first[:growth]
      assert_equal 0.0, first[:accelerator]
      assert_equal 0.0, first[:reducer]
    end
  end

  # O lote sintético tem current_period = agosto. Julho ancora nele (é o arquivo do mês
  # seguinte); agosto só tem o próprio arquivo e fica provisório; abril a junho caem no lote
  # mais antigo.
  test "cada competência ancora o Net MDR no arquivo do mês seguinte, ou declara a origem" do
    gama = @reports.find { |row| row[:name] == "MIC GAMA" }
    origem = gama[:months].to_h { |m| [ m[:period], m[:mdr_source] ] }

    assert_equal "closed", origem[Date.new(2026, 7, 1)]
    assert_equal "provisional", origem[Date.new(2026, 8, 1)]
    assert_equal %w[fallback fallback fallback], [ 4, 5, 6 ].map { |mes| origem[Date.new(2026, mes, 1)] }
  end

  # O NET MDR do Mapa é o realizado do mês anterior ao do arquivo (provado contra o extrato
  # de agosto/2026 do MIC GOIANIA 4). Com o arquivo de setembro importado, agosto deixa de ser
  # provisório e passa a usar o MDR desse arquivo — e julho continua com o do arquivo de agosto.
  test "o arquivo do mês seguinte fecha o Net MDR da competência" do
    agosto_antes = gama_month(@reports, Date.new(2026, 8, 1))
    # A planilha sintética tem competência fixa (agosto). O segundo import muda o conteúdo —
    # senão é recusado como duplicado — e o lote é datado de setembro à mão, que é o que a
    # consulta lê para saber de que mês é o arquivo.
    lojas = @lojas.map do |loja|
      loja.net_mdr.is_a?(Numeric) ? loja.dup.tap { |copia| copia.net_mdr = loja.net_mdr + 0.10 } : loja
    end
    setembro = import_synthetic_workbook(lojas:, filename: "BIN_TESTE_20260908.xlsx")
    setembro.update_columns(current_period: Date.new(2026, 9, 1))
    refresh_audit_views

    reports = RecurringEarningsQuery.new.by_sub_channel
    agosto = gama_month(reports, Date.new(2026, 8, 1))
    julho = gama_month(reports, Date.new(2026, 7, 1))

    assert_equal "closed", agosto[:mdr_source]
    assert_in_delta agosto_antes[:net_mdr] + 0.10, agosto[:net_mdr], 0.0001
    assert_in_delta agosto_antes[:net_mdr], julho[:net_mdr], 0.0001, "julho segue no arquivo de agosto"
  end

  def gama_month(reports, period)
    reports.find { |row| row[:name] == "MIC GAMA" }[:months].find { |m| m[:period] == period }
  end

  test "EC com MDR Inativo fica fora da média ponderada do mês" do
    gama = @reports.find { |row| row[:name] == "MIC GAMA" }
    with_mdr = @lojas.find { |loja| loja.sub_channel_name == "MIC GAMA" && loja.net_mdr.is_a?(Numeric) }

    gama[:months].each do |month|
      assert_in_delta with_mdr.net_mdr, month[:net_mdr], 0.0001, "MDR de #{month[:period]}"
    end
  end

  # "Net MDR da carteira (sem Flex)" é o cabeçalho da tabela de recorrência do Anexo C. O EC
  # da modalidade Flex sai da média que escolhe a faixa — o volume dele continua na base sobre
  # a qual a alíquota é aplicada, que é o que o contrato manda.
  test "EC da modalidade Flex fica fora da média ponderada do Net MDR" do
    flex_ec = Establishment.find_by!(ec: "50000001")
    antes = @reports.find { |row| row[:name] == "MIC GAMA" }[:months].first[:net_mdr]

    ApplicationRecord.connection.execute(
      "UPDATE map_snapshots SET financial_solutions = 'Flex' WHERE establishment_id = #{flex_ec.id}"
    )
    refresh_audit_views
    depois = RecurringEarningsQuery.new.by_sub_channel
      .find { |row| row[:name] == "MIC GAMA" }[:months].first

    assert_not_nil antes, "o EC precisa ter MDR, senão o teste é vácuo"
    # Era o único EC da GAMA com MDR; virando Flex, não sobra ninguém para a média.
    assert_nil depois[:net_mdr]
    assert_equal 0.0, depois[:recurring], "sem faixa de MDR não há alíquota, e o repasse é zero"
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
