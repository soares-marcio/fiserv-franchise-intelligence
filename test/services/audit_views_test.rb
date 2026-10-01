require "test_helper"

class AuditViewsTest < ActiveSupport::TestCase
  setup do
    @stores = BinWorkbook.default_stores
    @cutoff = BinWorkbook.cutoff_day(@stores)
    @batch = import_synthetic_workbook(stores: @stores)
    refresh_audit_views
  end

  test "lista o CNPJ que não vendeu nenhum dia do mês atual" do
    stop = @stores.find { |store| store.current_days.empty? }
    row = ReportScope.new(scope: organization_scope).stalled_companies.find { |row| row["cnpj"] == stop.cnpj }

    assert row, "CNPJ sem venda no mês precisa aparecer em clientes parados"
    assert_nil row["last_sale_day"]
    assert_equal @cutoff, row["days_without_sales"]
  end

  test "não lista quem vendeu até o dia de corte" do
    active = @stores.find { |store| store.current_days.keys.max == @cutoff }
    cnpjs = ReportScope.new(scope: organization_scope).stalled_companies.map { |row| row["cnpj"] }

    assert_not_includes cnpjs, active.cnpj
  end

  test "a view por subcanal separa o mês anterior cheio da base comparável" do
    rows = view_rows("audit_revenue_by_sub_channel").index_by { |row| row["sub_channel_name"] }

    @stores.group_by(&:sub_channel_name).each do |sub_channel_name, stores|
      row = rows.fetch(sub_channel_name)
      assert_equal sum_total(stores, :previous_days), row["previous_full_revenue"].to_d, sub_channel_name
      assert_equal sum_total(stores, :previous_days, upto: @cutoff), row["previous_revenue"].to_d, sub_channel_name
      assert_equal sum_total(stores, :current_days, upto: @cutoff), row["current_revenue"].to_d, sub_channel_name
    end
  end

  test "a view por empresa também expõe o mês anterior cheio" do
    rows = view_rows("audit_revenue_by_company").index_by { |row| row["cnpj"] }

    @stores.group_by(&:cnpj).each do |cnpj, stores|
      assert_equal sum_total(stores, :previous_days), rows.fetch(cnpj)["previous_full_revenue"].to_d, cnpj
    end
  end

  test "a view e o ReportScope chegam ao mesmo total com um canal só" do
    totals = ReportScope.new(scope: organization_scope).totals
    rows = view_rows("audit_revenue_by_sub_channel")

    assert_equal rows.sum { |row| row["previous_full_revenue"].to_d }, totals[:previous_full_revenue]
    assert_equal rows.sum { |row| row["previous_revenue"].to_d }, totals[:previous_revenue]
    assert_equal rows.sum { |row| row["current_revenue"].to_d }, totals[:current_revenue]
  end

  # O refresh roda logo depois de cada carga em massa, antes de o autoanalyze acordar: sem
  # estatísticas o planejador estimava as tabelas como vazias e as duas views de faturamento
  # levavam segundos em nested loops. O ANALYZE das fontes vem antes do primeiro REFRESH.
  test "refresh atualiza as estatísticas das tabelas-fonte antes de refrescar" do
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql]
    end
    AuditViews.refresh!
    ActiveSupport::Notifications.unsubscribe(subscriber)

    analyze = statements.index { |sql| sql.start_with?("ANALYZE ") }
    assert analyze, "nenhum ANALYZE antes do refresh"
    assert_operator analyze, :<, statements.index { |sql| sql.start_with?("REFRESH") }
    AuditViews::SOURCE_TABLES.each { |table| assert_includes statements[analyze], table }
  end

  # Toda tabela que uma view lê tem que estar na lista analisada, senão a view volta a
  # planejar sobre estatísticas velhas sem ninguém perceber.
  test "a lista de tabelas-fonte cobre tudo que as views leem" do
    connection = ApplicationRecord.connection
    AuditViews::NAMES.each do |view|
      definition = connection.select_value("SELECT pg_get_viewdef(#{connection.quote(view)})")
      tables = definition.scan(/public\.(\w+)/).flatten.uniq - AuditViews::NAMES
      assert_empty tables - AuditViews::SOURCE_TABLES, "#{view} lê tabelas fora de SOURCE_TABLES"
    end
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

    scope = ReportScope.new(scope: organization_scope)
    assert_empty scope.stalled_companies
    assert_empty scope.weekly_revenue
  end

  private

  def view_rows(name)
    ApplicationRecord.connection.exec_query("SELECT * FROM #{name}").to_a
  end

  def sum_total(stores, field, upto: nil)
    stores.sum do |store|
      store.public_send(field).sum { |day, amount| upto && day > upto ? 0 : amount }
    end.to_d
  end
end
