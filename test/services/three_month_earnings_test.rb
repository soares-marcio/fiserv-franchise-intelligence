require "test_helper"

# Página 3M de ponta a ponta: import sintético, view de credenciamento e cálculo ao vivo.
# Todos os esperados saem das lojas declaradas no BinWorkbook — nada fixado à mão.
class ThreeMonthEarningsTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

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

  # Repasse, MDR ponderado e acelerador/redutor migraram para o ganho recorrente
  # (RecurringEarningsQuery, coberto em recurring_earnings_test.rb): o 3M aplica só o
  # modelo dos primeiros 3 meses.
  test "nível 1 resume a safra: contagem de ECs e prêmio nas duas hipóteses" do
    # Safra de junho: o EC da GAMA credenciou em julho, então junho vem vazio.
    gama_june = @query.by_sub_channel.find { |row| row[:name] == "MIC GAMA" }
    assert_equal 0, gama_june[:prize][:accredited]

    july = [ Date.new(2026, 7, 1), Date.new(2026, 8, 1), Date.new(2026, 9, 1) ]
    gama = ThreeMonthEarningsQuery.new(periods: july).by_sub_channel
      .find { |row| row[:name] == "MIC GAMA" }
    gama_ec = @lojas.find { |loja| loja.ec == "50000001" }
    peak = [ gama_ec.total_m1, gama_ec.total_atual ].max

    assert_equal 1, gama[:prize][:accredited]
    assert_in_delta SubChannelCompensationRules::DIGITALIZATION_FEE, gama[:prize][:digitalization], 0.001
    assert_in_delta SubChannelCompensationRules.accreditation_bracket_value(peak, with_auto: false),
      gama[:prize][:addon_without_auto], 0.001
    assert_in_delta SubChannelCompensationRules.accreditation_bracket_value(peak, with_auto: true),
      gama[:prize][:addon_with_auto], 0.001
  end

  test "credenciamento em janela parcialmente coberta apura a marca d'água e expõe os meses" do
    gama_ec = @lojas.find { |loja| loja.ec == "50000001" }
    row = ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings WHERE establishment_id = " \
      "(SELECT id FROM establishments WHERE ec = '50000001')"
    ).to_a.sole

    # Janela do EC = jul/ago/set. O volume mensal cobre jul e ago; setembro não existe
    # na planilha — dois meses apurados, não três.
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
  end

  test "janela só parcialmente coberta apura o que existe e distingue de não apurável" do
    row = ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings WHERE establishment_id = " \
      "(SELECT id FROM establishments WHERE ec = '50000003')"
    ).to_a.sole

    # Credenciado em fev/2026: janela fev/mar/abr. Só abril tem volume mensal na
    # planilha sintética, então um mês é apurado — e o prêmio zero aqui é a faixa mais
    # baixa de verdade, não ausência de dado. months_observed separa os dois casos.
    assert_equal 1, row["months_observed"]
    april_total = BinWorkbook::OUTROS_VOLUMES.fetch("202604")
    assert_in_delta april_total, row["peak_month_revenue"].to_f, 0.001
    assert_in_delta SubChannelCompensationRules.accreditation_bracket_value(april_total, with_auto: false),
      row["addon_without_auto"].to_f, 0.001
    # Sem acesso ao app declarado: nada de digitalização.
    assert_equal 0, row["digitalization_amount"].to_f
  end

  # O Anexo C nomeia a coluna "C" como "com auto/flex" — modalidade **contratada** — e trata a
  # antecipação **realizada** como base de outra remuneração (1.1.2-B). São fatos diferentes, e
  # foi tratar um pelo outro que tornou a classificação impossível em 09/2026. SOLUÇÕES
  # FINANCEIRAS entrega a modalidade, e classifica 567 de 567 ECs no arquivo real.
  test "a modalidade contratada escolhe a coluna do adicional" do
    com_auto = view_row("50000001")
    sem_auto = view_row("50000003")

    assert_equal true, com_auto["auto_flex"]
    assert_in_delta com_auto["addon_with_auto"].to_f, com_auto["addon_amount"].to_f, 0.001

    assert_equal false, sem_auto["auto_flex"]
    assert_in_delta sem_auto["addon_without_auto"].to_f, sem_auto["addon_amount"].to_f, 0.001

    # As duas hipóteses continuam saindo: é contra elas que a resolução se confere.
    assert com_auto.key?("addon_without_auto")
    assert com_auto.key?("addon_with_auto")
  end

  # Sem modalidade na origem, nada é eleito: indefinido é NULL, e não zero. É a mesma distinção
  # que months_observed faz entre "faturou zero" e "não apurável".
  test "EC sem modalidade declarada fica indefinido, e não vira coluna B" do
    row = view_row("50000002")

    assert_nil row["auto_flex"]
    assert_nil row["addon_amount"]
    assert_nil row["m0_addon_amount"]
  end

  # A regra do contrato é sequencial: M0 paga a faixa, M1 paga a diferença se subiu de faixa,
  # M2 paga a faixa de M2 menos a maior já paga. O esperado é o mesmo laço em Ruby, sobre os
  # totais declarados na planilha — nada fixado à mão.
  test "as parcelas seguem a marca d'água mês a mês" do
    gama = @lojas.find { |loja| loja.ec == "50000001" }
    row = view_row("50000001")
    esperado = marca_dagua([ gama.total_m1, gama.total_atual, nil ], with_auto: true)

    assert_equal esperado, [ row["m0_addon_amount"], row["m1_addon_amount"],
      row["m2_addon_amount"] ].map { |v| v.to_f.round(2) }
    assert_in_delta esperado.sum, row["addon_amount"].to_f, 0.001,
      "a soma das parcelas fecha no total da janela"
  end

  # O caso em que a janela inteira é paga no último mês: sem M0 e M1 cobertos, a faixa de M2
  # carrega tudo. Prova que a parcela não nasce colada no M0.
  test "prêmio inteiro no M2 quando só o último mês da janela tem volume" do
    delta = ApplicationRecord.connection.quote(
      Establishment.find_by!(ec: "50000003").id
    )
    ApplicationRecord.connection.execute(
      "UPDATE monthly_volumes_consolidated SET amount = 55000 " \
      "WHERE establishment_id = #{delta} AND metric = 'total' AND period = DATE '2026-04-01'"
    )
    refresh_audit_views

    row = view_row("50000003")
    faixa = SubChannelCompensationRules.accreditation_bracket_value(55_000, with_auto: false)

    assert_equal [ 0.0, 0.0, faixa.to_f ], [ row["m0_addon_amount"], row["m1_addon_amount"],
      row["m2_addon_amount"] ].map { |v| v.to_f.round(2) }
    assert_in_delta faixa, row["addon_amount"].to_f, 0.001
  end

  # O invariante que autoriza trocar o total pelo detalhe: a soma das três parcelas é o total,
  # e o total é a coluna que a modalidade escolheu. Tudo é numeric, então a igualdade se testa
  # com <> e não com delta.
  test "as parcelas e a coluna resolvida fecham com as hipóteses, na view inteira" do
    divergentes = ApplicationRecord.connection.exec_query(<<~SQL).first
      SELECT COUNT(*) AS total FROM audit_accreditation_earnings
      WHERE m0_addon_amount + m1_addon_amount + m2_addon_amount <> addon_amount
         OR addon_amount <> CASE WHEN auto_flex THEN addon_with_auto ELSE addon_without_auto END
    SQL

    assert_equal 0, divergentes["total"]
    assert_operator ApplicationRecord.connection
      .select_value("SELECT COUNT(*) FROM audit_accreditation_earnings WHERE auto_flex IS NOT NULL"),
      :>, 0, "o invariante seria vácuo se nenhum EC estivesse classificado"
  end

  test "EC sem nenhum mês da janela coberto fica marcado como não apurável" do
    # Credenciamento muito anterior ao histórico: nenhuma das três competências existe.
    ApplicationRecord.connection.execute(
      "UPDATE map_snapshots SET accredited_on = DATE '2025-01-15' " \
      "WHERE establishment_id = (SELECT id FROM establishments WHERE ec = '50000003')"
    )
    refresh_audit_views

    row = ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings WHERE establishment_id = " \
      "(SELECT id FROM establishments WHERE ec = '50000003')"
    ).to_a.sole

    assert_equal 0, row["months_observed"]
    assert_nil row["peak_month_revenue"]
    assert_equal 0, row["addon_without_auto"].to_f
  end

  test "nível 2 traz só os ECs cujo M0 é o mês escolhido" do
    sub_channel = SubChannel.find_by!(name: "MIC GAMA")

    # M0 = julho: entra o EC credenciado em julho, e a janela dele é jul/ago/set.
    july = [ Date.new(2026, 7, 1), Date.new(2026, 8, 1), Date.new(2026, 9, 1) ]
    rows = ThreeMonthEarningsQuery.new(periods: july).by_establishment(sub_channel_id: sub_channel.id)
    assert_equal [ "50000001" ], rows.map { |row| row[:ec] }
    assert_equal 2, rows.sole[:accreditation]["months_observed"]

    # M0 = junho: o EC de julho não pertence a este mês de credenciamento, ainda que
    # julho apareça na janela de junho — é o M0 que define a pertinência, não a janela.
    june = [ Date.new(2026, 6, 1), Date.new(2026, 7, 1), Date.new(2026, 8, 1) ]
    assert_empty ThreeMonthEarningsQuery.new(periods: june).by_establishment(sub_channel_id: sub_channel.id)
  end

  test "sem volume mensal importado a consulta responde vazia, sem erro" do
    ApplicationRecord.connection.execute("DELETE FROM monthly_volumes_consolidated")
    assert_equal [], ThreeMonthEarningsQuery.new(periods: PERIODS).by_sub_channel
    assert_equal [], ThreeMonthEarningsQuery.available_periods
  end

  test "o nível 1 fica em cache por janela até a próxima consolidação" do
    # Devolve o mesmo objeto no fim: o rate_limit do controller prende o store na
    # definição da classe, e um NullStore novo deixaria aquele teste sem simulação.
    original_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    reports = @query.by_sub_channel

    # Só a consulta que monta a chave (carimbo da última consolidação).
    assert_equal reports, assert_queries_count(1) { @query.by_sub_channel }
    other_window = [ Date.new(2026, 5, 1), Date.new(2026, 6, 1), Date.new(2026, 7, 1) ]
    assert_queries_match(/monthly_volumes_consolidated/) do
      ThreeMonthEarningsQuery.new(periods: other_window).by_sub_channel
    end

    @lojas.first.dias_atual = @lojas.first.dias_atual.merge(1 => 999)
    import_synthetic_workbook(lojas: @lojas, filename: "BIN_TESTE_20260818.xlsx")
    assert_queries_match(/monthly_volumes_consolidated/) { ThreeMonthEarningsQuery.new(periods: PERIODS).by_sub_channel }
  ensure
    Rails.cache = original_store
  end

  # O nível 2 lê os mesmos insumos do nível 1 e ainda carrega EC por EC; a chave leva o
  # subcanal porque cada card abre um recorte diferente da mesma janela.
  test "o nível 2 fica em cache por subcanal e janela até a próxima consolidação" do
    original_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    sub_channel = SubChannel.find_by!(name: "MIC GAMA")
    july = [ Date.new(2026, 7, 1), Date.new(2026, 8, 1), Date.new(2026, 9, 1) ]
    query = ThreeMonthEarningsQuery.new(periods: july)
    rows = query.by_establishment(sub_channel_id: sub_channel.id)

    assert_equal rows, assert_queries_count(1) { query.by_establishment(sub_channel_id: sub_channel.id) }
    other = SubChannel.where.not(id: sub_channel.id).first
    assert_queries_match(/audit_accreditation_earnings/) { query.by_establishment(sub_channel_id: other.id) }

    @lojas.first.dias_atual = @lojas.first.dias_atual.merge(1 => 999)
    import_synthetic_workbook(lojas: @lojas, filename: "BIN_TESTE_20260818.xlsx")
    assert_queries_match(/monthly_volumes_consolidated/) do
      ThreeMonthEarningsQuery.new(periods: july).by_establishment(sub_channel_id: sub_channel.id)
    end
  ensure
    Rails.cache = original_store
  end
  private

  def view_row(ec)
    ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings WHERE establishment_id = " \
      "(SELECT id FROM establishments WHERE ec = '#{ec}')"
    ).to_a.sole
  end

  # O laço do contrato, em Ruby: a referência contra a qual o SQL da view é conferido.
  def marca_dagua(totais, with_auto:)
    pago = 0
    totais.map do |total|
      faixa = total.nil? ? 0 : SubChannelCompensationRules.accreditation_bracket_value(total, with_auto:)
      parcela = [ faixa - pago, 0 ].max
      pago += parcela
      parcela.to_f.round(2)
    end
  end
end
