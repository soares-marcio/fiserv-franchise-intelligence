require "test_helper"

class AuditViewsLatestRevenueBatchTest < ActiveSupport::TestCase
  test "map-only cadastro does not hide the last faturamento batch" do
    template = BinImport::Template.register!
    channel = Channel.create!(external_id: "1478", canal: "MASTER")
    sub_channel = channel.sub_channels.create!(sub_canal: "MIC A")
    company = Company.create!(cnpj: "12345678000191")
    establishment = Establishment.create!(ec: "11111111", company:, channel:)
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "a.xlsx",
      file_checksum: "checksum-revenue", competencia_m1: Date.new(2026, 7, 1),
      competencia_atual: Date.new(2026, 8, 1), dia_corte_mes_atual: 24, status: "validated"
    )
    RevenueSnapshot.create!(import_batch: batch, channel:, establishment:, sub_channel:)
    now = Time.current
    CompetenciaCoverage.upsert(
      {
        channel_id: channel.id, competencia: Date.new(2026, 8, 1), max_dia_conhecido: 24,
        fechado: false, ultimo_import_batch_id: batch.id, created_at: now, updated_at: now
      },
      unique_by: "index_competencia_coverages_on_channel_id_and_competencia"
    )
    AuditViews.refresh!

    assert_equal 1, view_count("audit_revenue_by_sub_channel")

    Operations::RegisterManually.call(
      "report_id" => "1478", "canal" => "MASTER", "sub_canal" => "MIC TESTE",
      "ec" => "12345678", "cnpj" => "12345678000195", "status_contrato" => "Active"
    )

    assert_equal 1, view_count("audit_revenue_by_sub_channel")
    assert_operator ImportBatch.where(channel:, status: "validated").count, :>=, 2
  end

  private

  def view_count(name)
    ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM #{name}").to_i
  end
end
