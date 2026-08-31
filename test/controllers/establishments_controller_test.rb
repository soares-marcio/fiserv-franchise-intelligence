require "test_helper"

class EstablishmentsControllerTest < ActionDispatch::IntegrationTest
  test "lista os campos de cadastro do snapshot atual do mapa" do
    seed_establishment

    get establishments_path

    assert_response :success
    assert_select "h1", text: "Estabelecimentos"
    assert_select "td", text: /EC 12345678/
    assert_select "p", text: "PADARIA CENTRAL"
    assert_select "td", text: /MIC GOIANIA 4/
    assert_select "td", text: /RUA A 100/
    assert_select "td", text: /5611201/
  end

  test "filtra estabelecimentos por nome" do
    seed_establishment

    get establishments_path, params: { q: "PADARIA" }
    assert_select "td", text: /EC 12345678/

    get establishments_path, params: { q: "inexistente" }
    assert_select "p", text: /Nenhum estabelecimento encontrado/
  end

  private

  def seed_establishment
    channel = Channel.create!(external_id: "1478", name: "MASTER")
    sub_channel = channel.sub_channels.create!(name: "MIC GOIANIA 4")
    company = Company.create!(cnpj: "12345678000195")
    establishment = Establishment.create!(ec: "12345678", company:, channel:)
    template = BinImport::Template.register!
    batch = ImportBatch.create!(
      channel:, import_template: template, source_filename: "manual",
      file_checksum: "seed-map", status: "validated"
    )
    MapSnapshot.create!(
      import_batch: batch, channel:, sub_channel:, establishment:,
      trade_name: "PADARIA CENTRAL", legal_name: "PADARIA CENTRAL LTDA",
      street_address: "RUA A 100", city: "GOIANIA", state: "GO", cep: "74000000",
      cnae_code: "5611201", cnae_description: "Restaurantes e similares",
      contract_status: "Active", performed_segment: "PJ3"
    )
  end
end
