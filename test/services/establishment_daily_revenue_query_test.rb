require "test_helper"

# Lançamentos diários de um EC, como o modal da tela de subcanal os mostra: um dia por
# linha, com o mês atual e o anterior lado a lado, dentro da faixa de dias escolhida.
class EstablishmentDailyRevenueQueryTest < ActiveSupport::TestCase
  ALFA = "MIC ALFA".freeze

  setup do
    @loja = BinWorkbook::Loja.new(
      ec: "30000001", cnpj: "11222333000181", sub_channel_name: ALFA,
      legal_name: "ALFA LANCHES LTDA", trade_name: "ALFA LANCHES", contract_status: "Active",
      dias_m1: { 1 => 100, 2 => 200, 25 => 700 }, dias_atual: { 1 => 150, 2 => 50, 10 => 300 }
    )
    import_synthetic_workbook(lojas: [ @loja ])
    @establishment = Establishment.find_by!(ec: @loja.ec)
    @scope = ReportScope.new(channel_id: @establishment.channel_id)
  end

  test "traz um dia por linha, com os dois meses lado a lado" do
    rows = daily(from_day: 1, to_day: 31)

    assert_equal (1..31).to_a, rows.map { |row| row["day"].to_i }
    assert_equal 150.to_d, valor(rows, 1, "current_amount")
    assert_equal 100.to_d, valor(rows, 1, "previous_amount")
    assert_equal 300.to_d, valor(rows, 10, "current_amount")
    assert_equal 700.to_d, valor(rows, 25, "previous_amount")
  end

  # Dia sem venda chega como zero na planilha e continua zero aqui: some-lo da lista
  # esconderia justamente o que o usuário abre o modal para ver.
  test "dia sem movimento aparece zerado, não sumido" do
    rows = daily(from_day: 1, to_day: 31)

    assert_equal 0.to_d, valor(rows, 3, "current_amount")
    assert_equal 0.to_d, valor(rows, 3, "previous_amount")
  end

  test "respeita a faixa de dias escolhida na tela" do
    rows = daily(from_day: 2, to_day: 10)

    assert_equal (2..10).to_a, rows.map { |row| row["day"].to_i }
    assert_equal 50.to_d, valor(rows, 2, "current_amount")
  end

  test "EC sem lançamento no recorte responde vazio, sem erro" do
    outro = Establishment.create!(
      ec: "99999999", channel_id: @establishment.channel_id, company_id: @establishment.company_id
    )

    assert_empty daily(from_day: 1, to_day: 31, establishment: outro).select { |row| row["current_amount"].to_d.positive? }
  end

  private

  def daily(from_day:, to_day:, establishment: @establishment)
    window = @scope.establishment_window(from_day:, to_day:)
    @scope.establishment_daily_revenues(establishment_id: establishment.id, window:)
  end

  def valor(rows, day, column)
    rows.find { |row| row["day"].to_i == day }[column].to_d
  end
end
