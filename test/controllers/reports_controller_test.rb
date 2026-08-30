require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "renders the audit page without data" do
    get reports_path
    assert_response :success
    assert_select "h1", text: "Auditoria de faturamento"
    assert_select "th", text: /Mês anterior cheio/
    assert_select "th", text: /Mês anterior comparável/
  end

  test "exports csv" do
    get reports_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Mês anterior (cheio)"
    assert_includes response.body, "Mês anterior comparável"
  end

  test "selects a channel and preserves it in exports" do
    selected = Channel.create!(external_id: "1", canal: "CANAL A")
    Channel.create!(external_id: "2", canal: "CANAL B")

    get reports_path(channel_id: selected.uuid)

    assert_response :success
    assert_select "select[name='channel_id'] option[selected]", text: "CANAL A"
    assert_select "select[name='channel_id'] option", text: "CANAL B"
    assert_select "a[href='#{reports_path(format: :csv, channel_id: selected.uuid)}']", text: "Exportar CSV"
    assert_select "a[href='#{reports_path(format: :xlsx, channel_id: selected.uuid)}']", text: "Exportar XLSX"
  end

  test "links each subchannel to its establishment listing" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)

    get reports_path

    assert_response :success
    assert_select "a[href='#{sub_channel_report_path(sub_channel)}']", text: "MIC A"
  end

  test "shows establishments that compose the subchannel totals" do
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

  test "filters the establishment listing by status and day range" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    suspended = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: ImportBatch.find_by!(channel:), channel:, sub_channel:,
      establishment: suspended, razao_social: "LOJA DOIS LTDA", nome_fantasia: "LOJA DOIS",
      status_contrato: "Suspended", fat_total_m1: 20, fat_total_mes_atual: 30
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

  test "searches and pages the establishment listing" do
    template = BinImport::Template.register!
    channel, sub_channel = seed_subchannel_revenue(template)
    second = Establishment.create!(
      ec: "22222222", company: Company.create!(cnpj: "12345678000192"), channel:
    )
    RevenueSnapshot.create!(
      import_batch: ImportBatch.find_by!(channel:), channel:, sub_channel:,
      establishment: second, razao_social: "LOJA DOIS LTDA", nome_fantasia: "LOJA DOIS",
      status_contrato: "Active", fat_total_m1: 20, fat_total_mes_atual: 30
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

  test "returns not found for an unknown subchannel" do
    get sub_channel_report_path(id: SecureRandom.uuid)
    assert_response :not_found
  end

  private

  def seed_subchannel_revenue(template)
    channel = Channel.create!(external_id: "A", canal: "CANAL A")
    company = Company.create!(cnpj: "12345678000191")
    establishment = Establishment.create!(ec: "11111111", company:, channel:)
    sub_channel = channel.sub_channels.create!(sub_canal: "MIC A")
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "a.xlsx",
      file_checksum: "checksum-reports-#{SecureRandom.hex(4)}",
      competencia_m1: Date.new(2026, 7, 1), competencia_atual: Date.new(2026, 8, 1),
      dia_corte_mes_atual: 24, status: "validated"
    )
    RevenueSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      razao_social: "LOJA UM LTDA", nome_fantasia: "LOJA UM", status_contrato: "Active",
      fat_total_m1: 80, fat_total_mes_atual: 100
    )
    MapSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      razao_social: "LOJA UM LTDA", nome_fantasia: "LOJA UM", status_contrato: "Active",
      data_credenciamento: Date.new(2024, 3, 15), data_ativacao: Date.new(2024, 4, 2)
    )
    now = Time.current
    CompetenciaCoverage.upsert_all(
      [
        {
          channel_id: channel.id, competencia: Date.new(2026, 7, 1), max_dia_conhecido: 31, fechado: true,
          ultimo_import_batch_id: batch.id, created_at: now, updated_at: now
        },
        {
          channel_id: channel.id, competencia: Date.new(2026, 8, 1), max_dia_conhecido: 24, fechado: false,
          ultimo_import_batch_id: batch.id, created_at: now, updated_at: now
        }
      ],
      unique_by: "index_competencia_coverages_on_channel_id_and_competencia"
    )
    DailyRevenueConsolidated.upsert_all(
      [
        {
          establishment_id: establishment.id, channel_id: channel.id, competencia: Date.new(2026, 7, 1),
          day: 24, amount: 80, provisional: false, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        },
        {
          establishment_id: establishment.id, channel_id: channel.id, competencia: Date.new(2026, 8, 1),
          day: 24, amount: 100, provisional: true, source_import_batch_id: batch.id, revised_count: 0,
          created_at: now, updated_at: now
        }
      ],
      unique_by: "index_daily_revenues_consolidated_primary"
    )
    [ channel, sub_channel ]
  end
end
