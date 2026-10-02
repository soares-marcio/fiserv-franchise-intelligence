require "test_helper"

# Campanha APP BIN (digitalização) como a Fiserv a paga no extrato: R$ 30 por CNPJ, no mês do
# primeiro acesso ao app, dentro da janela do credenciamento (M0–M2). A coluna do arquivo é
# "último acesso", então o primeiro acesso só é conhecido quando um lote mostrou o CNPJ sem
# acesso antes: o setup importa dois arquivos para produzir essa transição. Os esperados saem
# das lojas declaradas em BinWorkbook.app_campaign_lojas.
class AppCampaignTest < ActiveSupport::TestCase
  FEE = SubChannelCompensationRules::DIGITALIZATION_FEE

  setup do
    import_synthetic_workbook(stores: BinWorkbook.app_campaign_stores(accesses: false),
      filename: "BIN_TESTE_20260811.xlsx")
    @stores = BinWorkbook.app_campaign_stores
    import_synthetic_workbook(stores: @stores, filename: "BIN_TESTE_20260818.xlsx")
    refresh_audit_views
  end

  def view_row(ec)
    ApplicationRecord.connection.exec_query(
      "SELECT * FROM audit_accreditation_earnings WHERE establishment_id = " \
      "(SELECT id FROM establishments WHERE ec = '#{ec}')"
    ).to_a.sole
  end

  test "paga no mês do primeiro acesso observado, uma vez por CNPJ, no EC credenciado primeiro" do
    first_item = view_row("72000001")
    second = view_row("72000002")

    assert_in_delta FEE, first_item["digitalization_amount"].to_f, 0.001
    assert_equal Date.new(2026, 8, 1), first_item["digitalization_period"], "M1: mês do acesso, não do credenciamento"
    assert_equal 0, second["digitalization_amount"].to_f, "o segundo EC do mesmo CNPJ não paga de novo"
    assert_equal Date.new(2026, 8, 1), second["digitalization_period"], "o mês do acesso é do CNPJ"
    assert_equal true, second["has_app_access"]
  end

  # O CNPJ que já aparece com acesso no primeiro lote pode ter acessado antes de tudo que foi
  # importado — no extrato de agosto/2026, 20 dos 39 CNPJs que a leitura ingênua pagaria em
  # agosto já tinham sido pagos antes. Sem transição observada, vale a letra do Anexo C: M0.
  test "sem transição observada, a campanha cai em M0" do
    row = view_row("72000006")

    assert_equal Date.new(2026, 7, 1), row["digitalization_period"]
    assert_in_delta FEE, row["digitalization_amount"].to_f, 0.001
  end

  test "acesso depois de M2 não paga, e sem acesso também não" do
    late = view_row("72000003")
    without_app = view_row("72000004")
    at_limit = view_row("72000005")

    assert_equal 0, late["digitalization_amount"].to_f
    assert_equal Date.new(2026, 8, 1), late["digitalization_period"], "o mês do acesso fica registrado mesmo sem pagar"
    assert_equal 0, without_app["digitalization_amount"].to_f
    assert_nil without_app["digitalization_period"]
    assert_in_delta FEE, at_limit["digitalization_amount"].to_f, 0.001, "M2 ainda está na janela"
  end

  # "Último acesso" sobrescreve: um arquivo posterior com acesso mais recente não move o mês
  # pago, porque o primeiro acesso observado continua sendo o menor valor visto.
  test "um acesso mais recente num arquivo posterior não move o mês pago" do
    stores = @stores.map do |store|
      store.ec == "72000005" ? store.dup.tap { |copy| copy.app_access_at = "2026-09-02 08:00" } : store
    end
    import_synthetic_workbook(stores:, filename: "BIN_TESTE_20260908.xlsx")
    refresh_audit_views

    assert_equal Date.new(2026, 8, 1), view_row("72000005")["digitalization_period"]
    assert_in_delta FEE, view_row("72000005")["digitalization_amount"].to_f, 0.001
  end

  # No recorrente a digitalização cai na competência em que a campanha é paga, que é onde o
  # extrato a traz: dois CNPJs em agosto (M1 e M2) e o de M0 em julho.
  test "a digitalização entra na Participação do mês em que é paga" do
    theta = RecurringEarningsQuery.new(scope: organization_scope).by_sub_channel.find { |row| row[:name] == "MIC THETA" }
    by_month = theta[:months].to_h { |month| [ month[:period], month[:accreditation] ] }

    assert_in_delta 2 * FEE, by_month[Date.new(2026, 8, 1)], 0.001
    assert_in_delta FEE, by_month[Date.new(2026, 7, 1)], 0.001
  end
end
