require "test_helper"

# Uma organização não importa carteira de outra — e não descobre, ao tentar, nem o nome do
# Master nem o do EC alheio. As mensagens vão para a tela de lotes, então a neutralidade
# é conferida na origem, pelo Importer#call inteiro e não só pelo guard isolado.
class BinImport::OrganizationGuardTest < ActiveSupport::TestCase
  setup do
    @other = Organization.create!(name: "Outra Organização")
    # A carteira de B, importada de verdade: é o que A vai tentar tocar.
    import_synthetic_workbook(organization: @other, filename: "BIN_B_20260811.xlsx")
    @admin_a = admin_user
  end

  test "REPORT_ID de outra organização é recusado sem revelar o nome do Master" do
    error = assert_raises(ArgumentError) { import_file_as(@admin_a, filename: "BIN_A_20260812.xlsx") }

    assert_match(/não pertence à sua organização/, error.message)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}/, error.message)
    assert_no_match(/Outra Organização/, error.message)
    assert_equal 1, Channel.count, "nenhum Master novo pode nascer da recusa"
  end

  test "EC de outra organização é recusado sem revelar o canal nem o CNPJ" do
    # Mesmas lojas, REPORT_ID e CANAL novos: o Master seria de A, mas os ECs já são de B.
    error = assert_raises(ArgumentError) do
      import_file_as(@admin_a, filename: "BIN_A_20260812.xlsx", channel: "MASTER DE A", report_id: "7777")
    end

    assert_match(/fora da sua organização/, error.message)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CHANNEL)}|outro canal|outro CNPJ/, error.message)
    assert_equal 0, MapSnapshot.where(channel: Channel.find_by(external_id: "7777")).count
  end

  test "administrador da organização inaugura Master novo; colaborador não" do
    # ECs novos (os da planilha padrão já pertencem a B): oito dígitos, sem colisão.
    stores = BinWorkbook.default_stores.each_with_index.map do |store, i|
      store.class.new(**store.to_h.merge(ec: format("5%07d", i + 1)))
    end
    collaborator = scoped_user(permissions: [ Permission::BATCHES_UPLOAD ], email: "colab@exemplo.com")

    error = assert_raises(ArgumentError) do
      import_file_as(collaborator, stores:, filename: "BIN_COLAB_20260812.xlsx", channel: "MASTER DE A", report_id: "7777")
    end
    assert_match(/administrador da organização/, error.message)
    assert_nil Channel.find_by(external_id: "7777")

    batch = import_file_as(@admin_a, stores:, filename: "BIN_ADMIN_20260813.xlsx", channel: "MASTER DE A", report_id: "7777")
    assert_equal default_organization, batch.channel.organization
    assert_equal default_organization, batch.organization
  end

  test "o cadastro manual também não toca Master de outra organização" do
    error = assert_raises(ArgumentError) do
      Operations::RegisterManually.call(
        "organization" => default_organization, "report_id" => BinWorkbook::REPORT_ID,
        "channel_name" => BinWorkbook::CHANNEL, "sub_channel_name" => "MIC X",
        "ec" => "12345678", "cnpj" => "12345678000195", "contract_status" => "Active"
      )
    end

    assert_match(/não pertence à sua organização/, error.message)
  end

  private

  # Lote criado como a tela cria (autor e organização), depois o importador.
  def import_file_as(author, stores: BinWorkbook.default_stores, filename:, channel: BinWorkbook::CHANNEL,
    report_id: BinWorkbook::REPORT_ID)
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
    BinWorkbook.write(path, stores:, channel:, report_id:)
    # Duas planilhas iguais no mesmo segundo têm o mesmo checksum (ver CLAUDE.md): o lote
    # recusado de uma tentativa é reaproveitado pela seguinte, como a tela faz.
    ImportBatch.find_or_initialize_by(file_checksum: Digest::SHA256.file(path).hexdigest)
      .update!(organization: author.organization, source_filename: filename, status: "pending",
        uploaded_by: author, channel: nil, validation_errors: [])
    BinImport::Importer.new(path, source_filename: filename).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
