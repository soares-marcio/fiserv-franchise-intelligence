require "test_helper"

class EstablishmentTest < ActiveSupport::TestCase
  setup do
    @batch = import_synthetic_workbook
    @alfa = Establishment.find_by!(ec: "30000001")
    @beta = Establishment.find_by!(ec: "30000002")
  end

  test "busca por EC, CNPJ com máscara, nome, cidade, CNAE e subcanal" do
    {
      "30000002" => [ @beta ], "44.555.666/0001-72" => [ @beta ], "beta cafe" => [ @beta ],
      "BETA SERVICOS" => [ @beta ], "mic beta" => [ @beta ],
      "goiania" => Establishment.order(:ec).to_a
    }.each do |query, expected|
      assert_equal expected.map(&:ec), Establishment.search(query).order(:ec).map(&:ec), "por #{query.inspect}"
    end
    assert_empty Establishment.search("zzz")
  end

  test "um EC com três snapshots históricos aparece uma vez e pelo cadastro mais recente" do
    2.times { |i| historical_snapshot(@alfa, trade_name: "ALFA ANTIGA #{i}") }
    MapSnapshot.where(establishment: @alfa).order(:id).last.update!(trade_name: "ALFA ATUAL")

    assert_equal [ @alfa ], Establishment.search("alfa").where(id: @alfa.id).to_a
    assert_equal [ @alfa ], Establishment.search("alfa atual").to_a
    assert_equal 3, @alfa.map_snapshots.count
  end

  private

  # Cada planilha semanal deixa um snapshot novo; o lote fabricado aqui simula esse histórico.
  def historical_snapshot(establishment, trade_name:)
    batch = ImportBatch.create!(
      channel_id: @batch.channel_id, import_template_id: @batch.import_template_id,
      source_filename: "historico.xlsx", file_checksum: "historico-#{SecureRandom.hex(4)}",
      previous_period: @batch.previous_period, current_period: @batch.current_period,
      current_month_cutoff_day: @batch.current_month_cutoff_day, status: "validated"
    )
    establishment.map_snapshots.order(:id).first.dup.update!(import_batch: batch, trade_name:)
  end
end
