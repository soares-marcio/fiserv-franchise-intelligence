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
    assert_select "p", text: /Nenhum cliente encontrado/
  end

  test "a lista responde ao frame da busca ao vivo sem a casca" do
    seed_establishment

    get establishments_path(q: "PADARIA"), headers: { "Turbo-Frame" => "establishments" }

    assert_response :success
    assert_select "turbo-frame#establishments td", text: /EC 12345678/
    assert_select "header.topbar", count: 0

    get establishments_path
    assert_select "form[data-turbo-frame=establishments][data-controller=live-form]"
    assert_select "header.topbar", count: 1
  end

  test "agrupa os ECs do mesmo CNPJ numa linha e pagina por cliente" do
    import_synthetic_workbook

    get establishments_path
    assert_select "tbody tr", count: 2
    assert_select ".badge", text: /2 clientes\s+· 3 ECs/
    assert_select "tbody tr:first-child td:first-child", text: /EC 30000001\s+·\s+EC 90000001/
    assert_select "tbody tr:first-child td", text: /2 ECs/

    get establishments_path(per_page: 1)
    assert_select "tbody tr", count: 1
    assert_select "nav.pagination-bar .pagination-bar__status", text: "Página 1 de 2"
    assert_select "nav.pagination-bar a[href=?]", establishments_path(per_page: 1, page: 2), text: "Próxima"

    get establishments_path(per_page: 1, page: 9, q: "beta")
    assert_select "tbody tr", count: 1
    assert_select ".badge", text: /1 cliente\s+· 1 EC\b/
    assert_select "nav.pagination-bar", count: 0
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
