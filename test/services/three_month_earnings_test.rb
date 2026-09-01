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

  test "a view não classifica antecipação: as duas hipóteses saem sempre" do
    row = ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings LIMIT 1"
    ).to_a.sole

    # O campo do boarding não carrega esse sinal na origem, então nenhuma coluna de
    # classificação existe — só os dois valores, para a tela apresentar como hipótese.
    assert_not row.key?("auto_classified")
    assert row.key?("addon_without_auto")
    assert row.key?("addon_with_auto")
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
end
