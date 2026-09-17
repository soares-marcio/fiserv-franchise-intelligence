require "test_helper"

# Indicadores do Anexo B recomputados das lojas sintéticas: KAPPA reprova em tudo no mês
# atual e SIGMA cumpre tudo, e cada percentual sai das declarações da planilha.
class SubChannelIndicatorsTest < ActiveSupport::TestCase
  MES = BinWorkbook::CURRENT_PERIOD
  RULES = SubChannelIndicatorRules

  setup do
    @lojas = BinWorkbook.indicator_lojas
    import_synthetic_workbook(lojas: @lojas)
    # A competência atual nasce aberta; fechada, ganha leitura.
    fechar_mes_atual
    @reports = SubChannelIndicatorsQuery.new.by_sub_channel
    @kappa = @reports.find { |row| row[:name] == "MIC KAPPA" }
    @sigma = @reports.find { |row| row[:name] == "MIC SIGMA" }
    @kappa_lojas = @lojas.select { |loja| loja.sub_channel_name == "MIC KAPPA" }
    # A base do mês: quem não estava suspenso antes de ele começar.
    @base = @kappa_lojas.reject { |loja| loja.suspended_on && loja.suspended_on < MES }
  end

  def fechar_mes_atual(closed: true)
    ApplicationRecord.connection.execute(
      "UPDATE period_coverages SET closed = #{closed} WHERE period = DATE '#{MES}'"
    )
  end

  def agosto(report) = report[:months].find { |month| month[:period] == MES }

  test "a base do mês exclui quem já estava suspenso, e o descredenciamento conta quem saiu nele" do
    leitura = agosto(@kappa)[:readings][:attrition]
    suspensas = @base.count { |loja| loja.suspended_on&.between?(MES, MES.end_of_month) }

    assert_operator @kappa_lojas.size, :>, @base.size, "a fixture precisa de uma loja suspensa antes do mês"
    assert_equal @base.size, leitura[:denominator]
    assert_equal suspensas, leitura[:numerator]
    assert_in_delta suspensas * 100.0 / @base.size, leitura[:value], 0.001
    assert_equal :risk, leitura[:verdict]
    assert_equal :adequate, agosto(@sigma)[:readings][:attrition][:verdict]
  end

  test "volume transacional conta quem passou de R$ 10.000 em débito + crédito" do
    leitura = agosto(@kappa)[:readings][:volume]
    acima = @base.count do |loja|
      loja.debito(BinWorkbook::MES_ATUAL) + loja.credito(BinWorkbook::MES_ATUAL) > RULES::VOLUME_THRESHOLD
    end

    assert_equal acima, leitura[:numerator]
    assert_in_delta acima * 100.0 / @base.size, leitura[:value], 0.001
    assert_equal :risk, leitura[:verdict]
    assert_equal :adequate, agosto(@sigma)[:readings][:volume][:verdict]
  end

  test "ECs sem transação vêm do ATIVO NO MÊS ATUAL? do arquivo" do
    leitura = agosto(@kappa)[:readings][:activity]
    sem_transacao = @base.count { |loja| loja.dias_atual.empty? }

    assert_equal sem_transacao, leitura[:numerator]
    assert_in_delta sem_transacao * 100.0 / @base.size, leitura[:value], 0.001
    assert_equal :risk, leitura[:verdict]
    assert_equal :adequate, agosto(@sigma)[:readings][:activity][:verdict]
  end

  test "credenciamentos do mês são os ECs com DATA DE CREDENCIAMENTO nele" do
    credenciadas = @kappa_lojas.count { |loja| loja.accredited_on.between?(MES, MES.end_of_month) }

    assert_equal BinImport::Template::DEFAULT_VOLUME_MONTHS.size, @kappa[:months].size
    assert_equal credenciadas, agosto(@kappa)[:readings][:accreditations][:value]
    assert_equal :risk, agosto(@kappa)[:readings][:accreditations][:verdict]
    assert_equal 10, agosto(@sigma)[:readings][:accreditations][:value]
    assert_equal :adequate, agosto(@sigma)[:readings][:accreditations][:verdict]
  end

  test "qualidade das indicações é a fração das propostas do mês recusadas, pendentes na base" do
    leitura = agosto(@kappa)[:readings][:quality]
    propostas = @kappa_lojas.select { |loja| loja.proposta && loja.proposed_on.beginning_of_month == MES }
    recusadas = propostas.count { |loja| loja.proposal_status == RULES::REJECTED_STATUS }
    pendentes = propostas.count { |loja| loja.proposal_status == RULES::PENDING_STATUS }

    assert_operator pendentes, :>, 0, "a fixture precisa de uma proposta pendente"
    assert_equal propostas.size, leitura[:denominator]
    assert_equal recusadas, leitura[:numerator]
    assert_equal pendentes, leitura[:pending]
    assert_in_delta recusadas * 100.0 / propostas.size, leitura[:value], 0.001
    assert_equal :risk, leitura[:verdict]
    assert_equal :adequate, agosto(@sigma)[:readings][:quality][:verdict]
  end

  test "competência aberta mostra o valor e não a leitura" do
    fechar_mes_atual(closed: false)
    kappa = SubChannelIndicatorsQuery.new.by_sub_channel.find { |row| row[:name] == "MIC KAPPA" }
    mes = agosto(kappa)

    assert mes[:partial]
    mes[:readings].each do |indicator, reading|
      assert_not_nil reading[:value], "#{indicator} sem valor"
      assert_nil reading[:verdict], "#{indicator} com leitura em mês aberto"
    end
  end

  test "sem Mapa da competência, os indicadores de base ficam sem leitura; credenciamentos não" do
    julho = @kappa[:months].find { |month| month[:period] == BinWorkbook::PREVIOUS_PERIOD }

    %i[volume attrition activity].each do |indicator|
      assert_nil julho[:readings][indicator][:value], "#{indicator} com valor sem arquivo do mês"
      assert_nil julho[:readings][indicator][:verdict]
    end
    # A data de credenciamento vem do último Mapa: julho é zero de verdade, e zero é Risco.
    assert_equal 0, julho[:readings][:accreditations][:value]
    assert_equal :risk, julho[:readings][:accreditations][:verdict]
  end

  test "o retrato é o último mês fechado com leitura, e a sequência em Risco para no buraco" do
    assert_equal RULES::INDICATORS.size, @kappa[:risk_count]
    assert_equal 0, @sigma[:risk_count]
    assert_equal MES, @kappa[:latest][:volume][:period]
    # Volume só tem leitura no mês atual (não há arquivo de julho): a sequência é 1.
    assert_equal 1, @kappa[:risk_streaks][:volume]
    # Credenciamentos têm leitura em todo mês: KAPPA credenciou 3 em agosto e 0 em julho,
    # dois meses fechados seguidos abaixo de 5 — a cláusula 12.2 (xx) alcança.
    assert_operator @kappa[:risk_streaks][:accreditations], :>=, RULES::TERMINATION_MONTHS
    assert_equal 0, @sigma[:risk_streaks][:accreditations]
  end

  test "o filtro por Master restringe as carteiras" do
    outro = Channel.create!(external_id: "OUTRO", name: "OUTRO MASTER")

    assert_empty SubChannelIndicatorsQuery.new(channel_id: outro.id).by_sub_channel
    assert_equal 2, SubChannelIndicatorsQuery.new(channel_id: Channel.find_by!(name: BinWorkbook::CANAL).id).by_sub_channel.size
  end
end
