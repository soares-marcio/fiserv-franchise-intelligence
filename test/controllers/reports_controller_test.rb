require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "trilha de navegação: agrupamento do menu não vira link" do
    get stalled_reports_path

    assert_select "nav.breadcrumb-wrap a[href=?]", root_path, text: "Início"
    assert_select "nav.breadcrumb-wrap span.breadcrumb-section", text: "Dashboard"
    assert_select "nav.breadcrumb-wrap a", text: "Dashboard", count: 0
    assert_select "nav.breadcrumb-wrap span[aria-current=page]", text: "Clientes parados"
  end

  test "cabeçalho mostra há quanto tempo a carteira recebeu arquivo" do
    get reports_path
    assert_select "a.header-status[data-tone=rose][href=?]", import_batches_path,
      text: /Sem arquivo importado/

    import_synthetic_workbook
    get reports_path
    assert_select "a.header-status[data-tone=green]", text: /Arquivo hoje/
  end

  test "a busca do header aponta para o endpoint de busca global" do
    get reports_path

    assert_select "body[data-app-layout-search-url-value=?]", search_path
    assert_select ".search-modal input.search-modal__input[aria-label]"
    assert_select ".search-modal turbo-frame#global-search[target=_top]"
  end

  test "clientes parados e semanal abrem com o banco recém-criado" do
    [ *AuditViews::ALIGNED_VIEWS, "audit_weekly_revenue" ].each do |view|
      ApplicationRecord.connection.execute("REFRESH MATERIALIZED VIEW #{view} WITH NO DATA")
    end

    get stalled_reports_path
    assert_response :success

    get weekly_reports_path
    assert_response :success
  end

  test "a página 3M abre sem volume importado e explica a dependência da planilha" do
    get three_months_reports_path
    assert_response :success
    assert_select "h1", text: "Ganhos 3M por subcanal"
    assert_select ".empty-state", text: /depende das colunas de volume da planilha/
  end

  test "a página 3M abre com o banco recém-criado, view de credenciamento sem dados" do
    ApplicationRecord.connection.execute(
      "REFRESH MATERIALIZED VIEW audit_accreditation_earnings WITH NO DATA"
    )
    get three_months_reports_path
    assert_response :success
  end

  test "página 3M lista subcanais e navega para os cards de estabelecimento" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    get three_months_reports_path
    assert_response :success
    assert_select "td a", text: "MIC GAMA"

    sub_channel = SubChannel.find_by!(name: "MIC GAMA")
    get three_months_sub_channel_report_path(id: sub_channel.uuid, start_period: "2026-08")
    assert_response :success
    assert_select ".metric-label", text: "EC 50000001"
    # As duas hipóteses aparecem lado a lado, sempre — a classificação só destaca.
    assert_select ".badge", text: /Sem antecipação/
    assert_select ".badge", text: /Com antecipação/
  end

  test "renderiza a página de auditoria sem dados" do
    get reports_path
    assert_response :success
    assert_select "h1", text: "Auditoria de faturamento"
    assert_select "th", text: /Mês anterior cheio/
    assert_select "th", text: /Mês anterior comparável/
  end

  test "exporta CSV" do
    get reports_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Mês anterior (cheio)"
    assert_includes response.body, "Mês anterior comparável"
  end

  test "seleciona um canal e o preserva nas exportações" do
    selected = Channel.create!(external_id: "1", name: "CANAL A")
    Channel.create!(external_id: "2", name: "CANAL B")

    get reports_path(channel_id: selected.uuid)

    assert_response :success
    assert_select "select[name='channel_id'] option[selected]", text: "CANAL A"
    assert_select "select[name='channel_id'] option", text: "CANAL B"
    assert_select "a[href='#{reports_path(format: :csv, channel_id: selected.uuid)}']", text: "Exportar CSV"
    assert_select "a[href='#{reports_path(format: :xlsx, channel_id: selected.uuid)}']", text: "Exportar XLSX"
  end

  test "liga cada subcanal à sua listagem de estabelecimentos" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get reports_path

    assert_response :success
    assert_select "a[href='#{sub_channel_report_path(sub_channel)}']", text: "MIC A"
  end

  test "mostra os estabelecimentos que compõem os totais do subcanal" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid)

    assert_response :success
    assert_select "h1", text: "MIC A"
    assert_select "th", text: /Mês anterior cheio/
    assert_select "th", text: /Mês anterior comparável/
    assert_select "td", text: "11111111"
    assert_select "td", text: "12.345.678/0001-91"
    assert_select "td", text: /LOJA UM/
    assert_select "th", text: "Datas do ciclo"
    assert_select "dt", text: "Cred."
    assert_select "dt", text: "Ativ."
    assert_select "dt", text: "Susp."
    assert_select "dd", text: "15/03/2024"
    assert_select "dd", text: "02/04/2024"
    assert_select "tfoot", false
    assert_select "input[name='status[]']"
    assert_select "input[name='date_kind[]']"
    assert_select "input[name='from_date']"
    assert_select "input[name='to_date']"
    assert_select "input[name='q']"
    assert_select "a", text: "10"
    assert_select "a", text: "20"
    assert_select "a", text: "50"
    assert_select "a", text: "100"
    assert_select "[data-controller='tag-select']"
    assert_select "[data-controller='date-range-picker']"
    assert_select "#status_filter_trigger[role='combobox'][aria-controls='status_filter_menu']"
    assert_select "#date_kind_filter_trigger[role='combobox'][aria-controls='date_kind_filter_menu']"
    assert_select "#date_range_panel[role='dialog']"
    assert_select "input#status_Active[data-label='Ativo'][data-tone='success']"
    assert_select "button", text: "Limpar datas"
    assert_select "button", text: "Concluir"
    assert_select "a[href='#{reports_path(channel_id: channel.uuid)}']"
    assert_select "dialog.modal"
    assert_select "dialog.modal [data-revenue-days-modal-target='comparableHint']"
    assert_select "dialog.modal [data-revenue-days-modal-target='currentHint']"
    assert_select "dialog.modal th", text: "Variação"
    assert_select "dialog.modal th", text: "Mês anterior"
    assert_select "dialog.modal th", text: "Mês atual"
    assert_select "button", text: "Lançamentos"
    assert_select ".variation-chip--up [data-tip=?]", "Subiu"
    assert_select "table tbody td span.block", false
  end

  test "filtra a listagem de estabelecimentos por status e faixa de dias" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    suspended = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: ImportBatch.find_by!(channel:), channel:, sub_channel:,
      establishment: suspended, legal_name: "LOJA DOIS LTDA", trade_name: "LOJA DOIS",
      contract_status: "Suspended", previous_month_total: 20, current_month_total: 30
    )

    get sub_channel_report_path(
      sub_channel, channel_id: channel.uuid, status: [ "Active" ],
      date_kind: [ "credenciamento" ], from_date: "2024-03-01", to_date: "2024-03-31"
    )

    assert_response :success
    assert_select "td", text: "11111111"
    assert_select "td", text: "22222222", count: 0
    assert_select "input#status_Active[checked]"
    assert_select "input#date_kind_credenciamento[checked]"
    assert_select "input[name='from_date'][value='2024-03-01']"
  end

  test "busca e pagina a listagem de estabelecimentos" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    second = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: ImportBatch.find_by!(channel:), channel:, sub_channel:,
      establishment: second, legal_name: "LOJA DOIS LTDA", trade_name: "LOJA DOIS",
      contract_status: "Active", previous_month_total: 20, current_month_total: 30
    )

    get sub_channel_report_path(sub_channel, channel_id: channel.uuid, q: "loja dois")

    assert_response :success
    assert_select "td", text: "22222222"
    assert_select "td", text: "11111111", count: 0
    assert_select "input[name='q'][value='loja dois']"

    get sub_channel_report_path(
      sub_channel, channel_id: channel.uuid, per_page: 1, page: 2
    )

    assert_response :success
    assert_select "td", text: "22222222"
    assert_select "td", text: "11111111", count: 0
    assert_select "a", text: "Anterior"
    assert_select "a", text: "Próxima"
  end

  test "responde não encontrado para subcanal desconhecido" do
    get sub_channel_report_path(id: SecureRandom.uuid)
    assert_response :not_found
  end

  private

  def seed_subchannel_revenue(template)
    channel = Channel.create!(external_id: "A", name: "CANAL A")
    company = Company.create!(cnpj: "12345678000191")
    establishment = Establishment.create!(ec: "11111111", company:, channel:)
    sub_channel = channel.sub_channels.create!(name: "MIC A")
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "a.xlsx",
      file_checksum: "checksum-reports-#{SecureRandom.hex(4)}",
      previous_period: Date.new(2026, 7, 1), current_period: Date.new(2026, 8, 1),
      current_month_cutoff_day: 24, status: "validated"
    )
    RevenueSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      legal_name: "LOJA UM LTDA", trade_name: "LOJA UM", contract_status: "Active",
      previous_month_total: 80, current_month_total: 100
    )
    MapSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      legal_name: "LOJA UM LTDA", trade_name: "LOJA UM", contract_status: "Active",
      accredited_on: Date.new(2024, 3, 15), activated_on: Date.new(2024, 4, 2)
    )
    now = Time.current
    PeriodCoverage.upsert_all(
      [
        {
          channel_id: channel.id, period: Date.new(2026, 7, 1), max_known_day: 31, closed: true,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        },
        {
          channel_id: channel.id, period: Date.new(2026, 8, 1), max_known_day: 24, closed: false,
          last_import_batch_id: batch.id, created_at: now, updated_at: now
        }
      ],
      unique_by: "index_period_coverages_on_channel_id_and_period"
    )
    DailyRevenueConsolidated.upsert_all(
      [
        {
          establishment_id: establishment.id, channel_id: channel.id, period: Date.new(2026, 7, 1),
          day: 24, amount: 80, provisional: false, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        },
        {
          establishment_id: establishment.id, channel_id: channel.id, period: Date.new(2026, 8, 1),
          day: 24, amount: 100, provisional: true, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        }
      ],
      unique_by: "index_daily_revenues_consolidated_primary"
    )
    [ channel, sub_channel ]
  end
end
