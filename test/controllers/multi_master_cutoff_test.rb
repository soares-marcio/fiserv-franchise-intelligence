require "test_helper"

# O dia de corte que o administrador da organização vê quando o recorte tem mais de um
# Master. Duas regras que, juntas, fazem o corte parecer "parado" depois de um envio, e por
# isso ficam escritas aqui: com vários Masters vale o menor corte, e a cobertura de um
# Master nunca recua para um arquivo mais curto (homologação de 30/09/2026).
class MultiMasterCutoffTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    import_synthetic_workbook
    @canal_a = Channel.find_by!(name: BinWorkbook::CANAL)
    @corte_a = BinWorkbook.cutoff_day

    import_synthetic_workbook(lojas: lojas_b, filename: "BIN_B_20260812.xlsx",
      canal: "MASTER FRANQUEADO B", report_id: "8888")
    @canal_b = Channel.find_by!(name: "MASTER FRANQUEADO B")
    @corte_b = BinWorkbook.cutoff_day(lojas_b)
    assert_operator @corte_b, :>, @corte_a, "o teste precisa de dois cortes diferentes"

    sign_in_as(admin_user)
  end

  test "com todos os Masters, a tela usa o menor corte e avisa; com um Master, o corte dele" do
    get reports_path
    assert_response :success
    assert_match(/dia #{@corte_a}<\/strong>/, response.body)
    assert_match(/Masters estão em dias diferentes/, response.body)
    assert_match(/MASTER FRANQUEADO B: dia #{@corte_b} · #{Regexp.escape(BinWorkbook::CANAL)}: dia #{@corte_a}/, response.body,
      "a tela diz o corte de cada Master, do mais recente ao mais atrasado")

    get reports_path(channel_id: @canal_b.uuid)
    assert_match(/dia #{@corte_b}<\/strong>/, response.body)
    assert_no_match(/dias diferentes/, response.body)
  end

  test "ajustar o corte de um Master não move o corte da visão com todos, enquanto o outro ficar atrás" do
    lote_a = ImportBatch.validated.find_by!(channel: @canal_a)

    patch update_cutoff_import_batch_path(lote_a), params: { max_known_day: 30 }
    assert_redirected_to import_batch_path(lote_a)

    get reports_path(channel_id: @canal_a.uuid)
    assert_match(/dia 30<\/strong>/, response.body, "o Master ajustado passa a valer o corte novo")
    get reports_path
    assert_match(/dia #{@corte_b}<\/strong>/, response.body, "com todos, manda o Master que ficou atrás")
  end

  test "arquivo com menos dias não recua a cobertura do Master: o corte fica e a anomalia registra" do
    curtas = BinWorkbook.default_lojas.map do |loja|
      loja.class.new(**loja.to_h.merge(dias_atual: { 1 => 10, 2 => 20 }))
    end
    assert_operator BinWorkbook.cutoff_day(curtas), :<, @corte_a

    lote = import_synthetic_workbook(lojas: curtas, filename: "BIN_TESTE_20260813.xlsx")

    assert_equal 2, lote.current_month_cutoff_day, "o lote registra o corte do próprio arquivo"
    cobertura = PeriodCoverage.find_by!(channel: @canal_a, period: lote.current_period)
    assert_equal @corte_a, cobertura.max_known_day, "a cobertura do Master não recua"
    assert DataAnomaly.exists?(channel: @canal_a, anomaly_type: "batch_covers_fewer_days")

    get reports_path(channel_id: @canal_a.uuid)
    assert_match(/dia #{@corte_a}<\/strong>/, response.body)
  end

  private

  def lojas_b
    [
      BinWorkbook::Loja.new(
        ec: "70000001", cnpj: "99888777000166", sub_channel_name: "MIC OMEGA",
        legal_name: "OMEGA COMERCIO LTDA", trade_name: "OMEGA",
        contract_status: "Active", dias_m1: { 1 => 500 }, dias_atual: { 1 => 900, 28 => 100 }
      )
    ]
  end
end
