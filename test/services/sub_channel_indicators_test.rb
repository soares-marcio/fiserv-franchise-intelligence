require "test_helper"

# Indicadores do Anexo B recomputados das lojas sintéticas: KAPPA reprova em tudo no mês
# atual e SIGMA cumpre tudo, e cada percentual sai das declarações da planilha.
class SubChannelIndicatorsTest < ActiveSupport::TestCase
  MES = BinWorkbook::CURRENT_PERIOD
  RULES = SubChannelIndicatorRules

  setup do
    @stores = BinWorkbook.indicator_stores
    import_synthetic_workbook(stores: @stores)
    # A competência atual nasce aberta; fechada, ganha leitura.
    close_current_month
    @reports = SubChannelIndicatorsQuery.new(scope: organization_scope).by_sub_channel
    @kappa = @reports.find { |row| row[:name] == "MIC KAPPA" }
    @sigma = @reports.find { |row| row[:name] == "MIC SIGMA" }
    @kappa_stores = @stores.select { |store| store.sub_channel_name == "MIC KAPPA" }
    # A base do mês: quem não estava suspenso antes de ele começar.
    @base = @kappa_stores.reject { |store| store.suspended_on && store.suspended_on < MES }
  end

  def close_current_month(closed: true)
    ApplicationRecord.connection.execute(
      "UPDATE period_coverages SET closed = #{closed} WHERE period = DATE '#{MES}'"
    )
  end

  def august(report) = report[:months].find { |month| month[:period] == MES }

  test "a base do mês exclui quem já estava suspenso, e o descredenciamento conta quem saiu nele" do
    reading = august(@kappa)[:readings][:attrition]
    suspended = @base.count { |store| store.suspended_on&.between?(MES, MES.end_of_month) }

    assert_operator @kappa_stores.size, :>, @base.size, "a fixture precisa de uma loja suspensa antes do mês"
    assert_equal @base.size, reading[:denominator]
    assert_equal suspended, reading[:numerator]
    assert_in_delta suspended * 100.0 / @base.size, reading[:value], 0.001
    assert_equal :risk, reading[:verdict]
    assert_equal :adequate, august(@sigma)[:readings][:attrition][:verdict]
  end

  test "volume transacional conta quem passou de R$ 10.000 em débito + crédito" do
    reading = august(@kappa)[:readings][:volume]
    above = @base.count do |store|
      store.debit(BinWorkbook::MES_ATUAL) + store.credit(BinWorkbook::MES_ATUAL) > RULES::VOLUME_THRESHOLD
    end

    assert_equal above, reading[:numerator]
    assert_in_delta above * 100.0 / @base.size, reading[:value], 0.001
    assert_equal :risk, reading[:verdict]
    assert_equal :adequate, august(@sigma)[:readings][:volume][:verdict]
  end

  test "ECs sem transação vêm do ATIVO NO MÊS ATUAL? do arquivo" do
    reading = august(@kappa)[:readings][:activity]
    without_transaction = @base.count { |store| store.current_days.empty? }

    assert_equal without_transaction, reading[:numerator]
    assert_in_delta without_transaction * 100.0 / @base.size, reading[:value], 0.001
    assert_equal :risk, reading[:verdict]
    assert_equal :adequate, august(@sigma)[:readings][:activity][:verdict]
  end

  test "credenciamentos do mês são os ECs com DATA DE CREDENCIAMENTO nele" do
    accredited = @kappa_stores.count { |store| store.accredited_on.between?(MES, MES.end_of_month) }

    assert_equal BinImport::Template::DEFAULT_VOLUME_MONTHS.size, @kappa[:months].size
    assert_equal accredited, august(@kappa)[:readings][:accreditations][:value]
    assert_equal :risk, august(@kappa)[:readings][:accreditations][:verdict]
    assert_equal 10, august(@sigma)[:readings][:accreditations][:value]
    assert_equal :adequate, august(@sigma)[:readings][:accreditations][:verdict]
  end

  test "qualidade das indicações é a fração das propostas do mês recusadas, pendentes na base" do
    reading = august(@kappa)[:readings][:quality]
    proposals = @kappa_stores.select { |store| store.proposal && store.proposed_on.beginning_of_month == MES }
    rejected = proposals.count { |store| store.proposal_status == RULES::REJECTED_STATUS }
    pending_ones = proposals.count { |store| store.proposal_status == RULES::PENDING_STATUS }

    assert_operator pending_ones, :>, 0, "a fixture precisa de uma proposta pendente"
    assert_equal proposals.size, reading[:denominator]
    assert_equal rejected, reading[:numerator]
    assert_equal pending_ones, reading[:pending]
    assert_in_delta rejected * 100.0 / proposals.size, reading[:value], 0.001
    assert_equal :risk, reading[:verdict]
    assert_equal :adequate, august(@sigma)[:readings][:quality][:verdict]
  end

  test "competência aberta mostra o valor e não a leitura" do
    close_current_month(closed: false)
    kappa = SubChannelIndicatorsQuery.new(scope: organization_scope).by_sub_channel.find { |row| row[:name] == "MIC KAPPA" }
    month = august(kappa)

    assert month[:partial]
    month[:readings].each do |indicator, reading|
      assert_not_nil reading[:value], "#{indicator} sem valor"
      assert_nil reading[:verdict], "#{indicator} com leitura em mês aberto"
    end
  end

  test "sem Mapa da competência, os indicadores de base ficam sem leitura; credenciamentos não" do
    july = @kappa[:months].find { |month| month[:period] == BinWorkbook::PREVIOUS_PERIOD }

    %i[volume attrition activity].each do |indicator|
      assert_nil july[:readings][indicator][:value], "#{indicator} com valor sem arquivo do mês"
      assert_nil july[:readings][indicator][:verdict]
    end
    # A data de credenciamento vem do último Mapa: julho é zero de verdade, e zero é Risco.
    assert_equal 0, july[:readings][:accreditations][:value]
    assert_equal :risk, july[:readings][:accreditations][:verdict]
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
    another = Channel.create!(organization: default_organization, external_id: "OUTRO", name: "OUTRO MASTER")

    assert_empty SubChannelIndicatorsQuery.new(scope: channel_scope(another.id)).by_sub_channel
    assert_equal 2, SubChannelIndicatorsQuery.new(scope: channel_scope(Channel.find_by!(name: BinWorkbook::CHANNEL).id)).by_sub_channel.size
  end

  # Homologação de 29/09/2026: quem tinha um MIC via os dez do Master. Credenciamentos e
  # base recortavam só pelo canal, e a lista de carteiras saía do que essas consultas
  # devolviam. O recorte por MIC tem de valer em cada uma das três fontes.
  test "quem tem um MIC vê só aquele MIC, com os mesmos números" do
    kappa = SubChannel.find_by!(name: "MIC KAPPA")

    scoped = SubChannelIndicatorsQuery.new(scope: mic_scope(kappa)).by_sub_channel

    assert_equal [ "MIC KAPPA" ], scoped.map { |row| row[:name] }
    assert_equal august(@kappa)[:readings], august(scoped.first)[:readings],
      "o recorte muda quem aparece, não o que se apura de quem aparece"
  end
end
