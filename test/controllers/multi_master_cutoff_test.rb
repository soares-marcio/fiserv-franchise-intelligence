require "test_helper"

# O dia de corte que o administrador da organização vê quando o recorte tem mais de um
# Master. Duas regras que, juntas, fazem o corte parecer "parado" depois de um envio, e por
# isso ficam escritas aqui: com vários Masters vale o menor corte, e a cobertura de um
# Master nunca recua para um arquivo mais curto (homologação de 30/09/2026).
class MultiMasterCutoffTest < ActionDispatch::IntegrationTest
  self.skip_default_login = true

  setup do
    import_synthetic_workbook
    @channel_a = Channel.find_by!(name: BinWorkbook::CHANNEL)
    @cutoff_a = BinWorkbook.cutoff_day

    import_synthetic_workbook(stores: stores_b, filename: "BIN_B_20260812.xlsx",
      channel: "MASTER FRANQUEADO B", report_id: "8888")
    @channel_b = Channel.find_by!(name: "MASTER FRANQUEADO B")
    @cutoff_b = BinWorkbook.cutoff_day(stores_b)
    assert_operator @cutoff_b, :>, @cutoff_a, "o teste precisa de dois cortes diferentes"

    sign_in_as(admin_user)
  end

  test "com todos os Masters, a tela usa o menor corte e avisa; com um Master, o corte dele" do
    get reports_path
    assert_response :success
    assert_match(/dia #{@cutoff_a}<\/strong>/, response.body)
    assert_match(/Masters estão em dias diferentes/, response.body)
    assert_match(/MASTER FRANQUEADO B: dia #{@cutoff_b} · #{Regexp.escape(BinWorkbook::CHANNEL)}: dia #{@cutoff_a}/, response.body,
      "a tela diz o corte de cada Master, do mais recente ao mais atrasado")

    get reports_path(channel_id: @channel_b.uuid)
    assert_match(/dia #{@cutoff_b}<\/strong>/, response.body)
    assert_no_match(/dias diferentes/, response.body)
  end

  test "ajustar o corte de um Master não move o corte da visão com todos, enquanto o outro ficar atrás" do
    batch_a = ImportBatch.validated.find_by!(channel: @channel_a)

    patch update_cutoff_import_batch_path(batch_a), params: { max_known_day: 30 }
    assert_redirected_to import_batch_path(batch_a)

    get reports_path(channel_id: @channel_a.uuid)
    assert_match(/dia 30<\/strong>/, response.body, "o Master ajustado passa a valer o corte novo")
    get reports_path
    assert_match(/dia #{@cutoff_b}<\/strong>/, response.body, "com todos, manda o Master que ficou atrás")
  end

  test "arquivo com menos dias não recua a cobertura do Master: o corte fica e a anomalia registra" do
    short_ones = BinWorkbook.default_stores.map do |store|
      store.class.new(**store.to_h.merge(current_days: { 1 => 10, 2 => 20 }))
    end
    assert_operator BinWorkbook.cutoff_day(short_ones), :<, @cutoff_a

    batch = import_synthetic_workbook(stores: short_ones, filename: "BIN_TESTE_20260813.xlsx")

    assert_equal 2, batch.current_month_cutoff_day, "o lote registra o corte do próprio arquivo"
    coverage = PeriodCoverage.find_by!(channel: @channel_a, period: batch.current_period)
    assert_equal @cutoff_a, coverage.max_known_day, "a cobertura do Master não recua"
    assert DataAnomaly.exists?(channel: @channel_a, anomaly_type: "batch_covers_fewer_days")

    get reports_path(channel_id: @channel_a.uuid)
    assert_match(/dia #{@cutoff_a}<\/strong>/, response.body)
  end

  # A cobertura é guardada por Master e por mês: com dois Masters, cada competência tinha
  # duas linhas, e o Semanal oferecia "setembro, setembro, agosto, agosto", com a seta de
  # mês anterior podendo cair no mesmo mês e a comparação usando o corte de um Master só
  # (homologação de 09/10/2026).
  test "o Semanal lista cada competência uma vez, anda mês a mês e usa o corte mais atrasado" do
    get weekly_reports_path

    assert_response :success
    options = css_select("select#period option").map { |option| option["value"] }
    assert_equal options.uniq, options, "competência repetida no seletor"
    assert_operator options.size, :>=, 2

    current, older = options.first(2)
    assert_select "a[aria-label='Competência anterior'][href*=?]", "period=#{older}"
    assert_match "até o dia #{@cutoff_a}", response.body, "vale o corte do Master mais atrasado"
    assert_no_match "até o dia #{@cutoff_b}", response.body
    assert_not_equal current, older
  end

  private

  def stores_b
    [
      BinWorkbook::Store.new(
        ec: "70000001", cnpj: "99888777000166", sub_channel_name: "MIC OMEGA",
        legal_name: "OMEGA COMERCIO LTDA", trade_name: "OMEGA",
        contract_status: "Active", previous_days: { 1 => 500 }, current_days: { 1 => 900, 28 => 100 }
      )
    ]
  end
end
