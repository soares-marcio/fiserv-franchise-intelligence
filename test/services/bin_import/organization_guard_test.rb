require "test_helper"

# Uma organização não importa carteira de outra — e não descobre, ao tentar, nem o nome do
# Master nem o do EC alheio. As mensagens vão para a tela de lotes, então a neutralidade
# é conferida na origem, pelo Importer#call inteiro e não só pelo guard isolado.
class BinImport::OrganizationGuardTest < ActiveSupport::TestCase
  setup do
    @outra = Organization.create!(name: "Outra Organização")
    # A carteira de B, importada de verdade: é o que A vai tentar tocar.
    import_synthetic_workbook(organization: @outra, filename: "BIN_B_20260811.xlsx")
    @admin_a = admin_user
  end

  test "REPORT_ID de outra organização é recusado sem revelar o nome do Master" do
    erro = assert_raises(ArgumentError) { importar_como(@admin_a, filename: "BIN_A_20260812.xlsx") }

    assert_match(/não pertence à sua organização/, erro.message)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CANAL)}/, erro.message)
    assert_no_match(/Outra Organização/, erro.message)
    assert_equal 1, Channel.count, "nenhum Master novo pode nascer da recusa"
  end

  test "EC de outra organização é recusado sem revelar o canal nem o CNPJ" do
    # Mesmas lojas, REPORT_ID e CANAL novos: o Master seria de A, mas os ECs já são de B.
    erro = assert_raises(ArgumentError) do
      importar_como(@admin_a, filename: "BIN_A_20260812.xlsx", canal: "MASTER DE A", report_id: "7777")
    end

    assert_match(/fora da sua organização/, erro.message)
    assert_no_match(/#{Regexp.escape(BinWorkbook::CANAL)}|outro canal|outro CNPJ/, erro.message)
    assert_equal 0, MapSnapshot.where(channel: Channel.find_by(external_id: "7777")).count
  end

  test "administrador da organização inaugura Master novo; colaborador não" do
    # ECs novos (os da planilha padrão já pertencem a B): oito dígitos, sem colisão.
    lojas = BinWorkbook.default_lojas.each_with_index.map do |loja, i|
      loja.class.new(**loja.to_h.merge(ec: format("5%07d", i + 1)))
    end
    colaborador = scoped_user(permissions: [ Permission::BATCHES_UPLOAD ], email: "colab@exemplo.com")

    erro = assert_raises(ArgumentError) do
      importar_como(colaborador, lojas:, filename: "BIN_COLAB_20260812.xlsx", canal: "MASTER DE A", report_id: "7777")
    end
    assert_match(/administrador da organização/, erro.message)
    assert_nil Channel.find_by(external_id: "7777")

    lote = importar_como(@admin_a, lojas:, filename: "BIN_ADMIN_20260813.xlsx", canal: "MASTER DE A", report_id: "7777")
    assert_equal default_organization, lote.channel.organization
    assert_equal default_organization, lote.organization
  end

  test "o cadastro manual também não toca Master de outra organização" do
    erro = assert_raises(ArgumentError) do
      Operations::RegisterManually.call(
        "organization" => default_organization, "report_id" => BinWorkbook::REPORT_ID,
        "channel_name" => BinWorkbook::CANAL, "sub_channel_name" => "MIC X",
        "ec" => "12345678", "cnpj" => "12345678000195", "contract_status" => "Active"
      )
    end

    assert_match(/não pertence à sua organização/, erro.message)
  end

  private

  # Lote criado como a tela cria (autor e organização), depois o importador.
  def importar_como(autor, lojas: BinWorkbook.default_lojas, filename:, canal: BinWorkbook::CANAL,
    report_id: BinWorkbook::REPORT_ID)
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{filename}")
    BinWorkbook.write(path, lojas:, canal:, report_id:)
    # Duas planilhas iguais no mesmo segundo têm o mesmo checksum (ver CLAUDE.md): o lote
    # recusado de uma tentativa é reaproveitado pela seguinte, como a tela faz.
    ImportBatch.find_or_initialize_by(file_checksum: Digest::SHA256.file(path).hexdigest)
      .update!(organization: autor.organization, source_filename: filename, status: "pending",
        uploaded_by: autor, channel: nil, validation_errors: [])
    BinImport::Importer.new(path, source_filename: filename).call
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
