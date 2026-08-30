require "test_helper"

class EstablishmentsControllerTest < ActionDispatch::IntegrationTest
  test "lists cadastro fields from the current map snapshot" do
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

  test "filters establishments by name" do
    seed_establishment

    get establishments_path, params: { q: "PADARIA" }
    assert_select "td", text: /EC 12345678/

    get establishments_path, params: { q: "inexistente" }
    assert_select "p", text: /Nenhum estabelecimento encontrado/
  end

  test "renders a grouped new form" do
    get new_establishment_path

    assert_response :success
    assert_select "h1", text: "Cadastrar estabelecimento"
    assert_select "label", text: /Razão social/
    assert_select "label", text: /Nome fantasia/
    assert_select "label", text: /Endereço/
    assert_select "label", text: /CNAE/
    assert_select "input[name='manual_entry[dia_01_m1]'][type='number']"
    assert_select "input[name='manual_entry[dia_31]'][type='number']"
    assert_select "label", text: "Report", count: 0
  end

  test "creates a manual client and shows the cadastro" do
    post establishments_path, params: {
      manual_entry: {
        report_id: "1478", channel_name: "MASTER", sub_channel_name: "MIC TESTE",
        ec: "12345678", cnpj: "12345678000195", contract_status: "Active",
        legal_name: "RAZAO", trade_name: "FANTASIA",
        street_address: "RUA B 20", cnae_code: "5611201"
      }
    }

    establishment = Establishment.find_by(ec: "12345678")
    assert_redirected_to establishment_path(establishment)
    follow_redirect!
    assert_select "h1", text: "FANTASIA"
    assert_select "dd", text: "RUA B 20"
    assert_select "dd", text: "5611201"
  end

  test "rejects an invalid CNPJ on the form" do
    post establishments_path, params: {
      manual_entry: {
        report_id: "1478", channel_name: "MASTER", sub_channel_name: "MIC TESTE",
        ec: "12345678", cnpj: "123", contract_status: "Active"
      }
    }

    assert_response :unprocessable_entity
    assert_select ".alert", text: "CNPJ inválido"
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
