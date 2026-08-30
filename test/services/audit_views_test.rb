require "test_helper"

class AuditViewsTest < ActiveSupport::TestCase
  setup do
    @lojas = BinWorkbook.default_lojas
    @cutoff = BinWorkbook.cutoff_day(@lojas)
    @batch = import_synthetic_workbook(lojas: @lojas)
    refresh_audit_views
  end

  test "lista o CNPJ que não vendeu nenhum dia do mês atual" do
    parada = @lojas.find { |loja| loja.dias_atual.empty? }
    linha = ReportScope.new.stalled_companies.find { |row| row["cnpj"] == parada.cnpj }

    assert linha, "CNPJ sem venda no mês precisa aparecer em clientes parados"
    assert_nil linha["last_sale_day"]
    assert_equal @cutoff, linha["dias_sem_venda"]
  end

  test "não lista quem vendeu até o dia de corte" do
    ativa = @lojas.find { |loja| loja.dias_atual.keys.max == @cutoff }
    cnpjs = ReportScope.new.stalled_companies.map { |row| row["cnpj"] }

    assert_not_includes cnpjs, ativa.cnpj
  end

  test "a view por subcanal separa o mês anterior cheio da base comparável" do
    linhas = view_rows("audit_revenue_by_sub_channel").index_by { |row| row["sub_channel_name"] }

    @lojas.group_by(&:name).each do |sub_channel_name, lojas|
      linha = linhas.fetch(sub_channel_name)
      assert_equal soma(lojas, :dias_m1), linha["faturamento_m1_cheio"].to_d, sub_channel_name
      assert_equal soma(lojas, :dias_m1, ate: @cutoff), linha["faturamento_m1"].to_d, sub_channel_name
      assert_equal soma(lojas, :dias_atual, ate: @cutoff), linha["faturamento_atual"].to_d, sub_channel_name
    end
  end

  test "a view por empresa também expõe o mês anterior cheio" do
    linhas = view_rows("audit_revenue_by_company").index_by { |row| row["cnpj"] }

    @lojas.group_by(&:cnpj).each do |cnpj, lojas|
      assert_equal soma(lojas, :dias_m1), linhas.fetch(cnpj)["faturamento_m1_cheio"].to_d, cnpj
    end
  end

  test "a view e o ReportScope chegam ao mesmo total com um canal só" do
    totals = ReportScope.new.totals
    linhas = view_rows("audit_revenue_by_sub_channel")

    assert_equal linhas.sum { |row| row["faturamento_m1_cheio"].to_d }, totals[:faturamento_m1_cheio]
    assert_equal linhas.sum { |row| row["faturamento_m1"].to_d }, totals[:faturamento_m1]
    assert_equal linhas.sum { |row| row["faturamento_atual"].to_d }, totals[:faturamento_atual]
  end

  test "refresh não quebra quando chamado dentro de uma transação" do
    assert_nothing_raised { ApplicationRecord.transaction { AuditViews.refresh! } }
  end

  test "view recém-criada não é elegível a CONCURRENTLY" do
    ApplicationRecord.connection.execute("REFRESH MATERIALIZED VIEW audit_weekly_revenue WITH NO DATA")

    assert_not AuditViews.populated?("audit_weekly_revenue"),
      "banco novo carrega as views WITH NO DATA; o primeiro refresh precisa ser bloqueante"
    assert_nothing_raised { AuditViews.refresh! }
    assert AuditViews.populated?("audit_weekly_revenue")
  end

  test "relatórios de view respondem vazio antes do primeiro import" do
    AuditViews::ALIGNED_VIEWS.each do |view|
      ApplicationRecord.connection.execute("REFRESH MATERIALIZED VIEW #{view} WITH NO DATA")
    end
    ApplicationRecord.connection.execute("REFRESH MATERIALIZED VIEW audit_weekly_revenue WITH NO DATA")

    scope = ReportScope.new
    assert_empty scope.stalled_companies
    assert_empty scope.weekly_revenue
  end

  private

  def view_rows(name)
    ApplicationRecord.connection.exec_query("SELECT * FROM #{name}").to_a
  end

  def soma(lojas, campo, ate: nil)
    lojas.sum do |loja|
      loja.public_send(campo).sum { |day, amount| ate && day > ate ? 0 : amount }
    end.to_d
  end
end
