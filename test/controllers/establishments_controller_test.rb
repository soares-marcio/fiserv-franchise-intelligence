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

  # A linha da listagem por subcanal mostrava NET MDR e o resumo de equipamentos; a página
  # do próprio EC, não. Quem clica para "ver mais" via menos do que já tinha visto.
  test "o detalhe do EC mostra NET MDR e todos os terminais do mapa" do
    establishment = seed_establishment(
      net_mdr: 0.299, smart_pos_count: 2, other_pos_count: 1, mps_count: 3,
      pin_count: 4, other_terminals_count: 5, tef_count: 0, tap_on_phone_count: 0,
      has_payment_link: true
    )

    get establishment_path(establishment)

    assert_response :success
    assert_select "dt", text: "NET MDR"
    assert_select "dd", text: "0,29%"
    assert_select "dt", text: "Resumo"
    assert_select "dd", text: "Link pgto · 3 POS · 3 MPS · 4 PIN · +5 outros"
    assert_select "dt", text: "Demais POS"
    assert_select "dt", text: "MPS"
    assert_select "dt", text: "PIN"
    assert_select "dt", text: "Outros terminais"
  end

  test "EC com MDR inativo mostra Inativo, não o número" do
    establishment = seed_establishment(net_mdr: 0.299, net_mdr_status: "Inativo")

    get establishment_path(establishment)

    assert_select "dd", text: "Inativo"
  end

  private

  def seed_establishment(**snapshot_attributes)
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
      contract_status: "Active", performed_segment: "PJ3", **snapshot_attributes
    )
    establishment
  end

  # A linha precisa levar ao cadastro, como a busca global leva: sem isso o único caminho
  # eram os chips de EC, que passavam despercebidos no rodapé da célula.
  test "o nome do cliente na listagem leva ao cadastro do EC de referência" do
    import_synthetic_workbook
    establishment = Establishment.find_by!(ec: "30000001")

    get establishments_path

    assert_response :success
    assert_select "tbody a.establishment-link[href=?]", establishment_path(establishment)
    # A listagem vive num turbo-frame e o cadastro não o tem: sem escapar para _top, o Turbo
    # responde "Content missing" e a tela fica em branco.
    assert_select "tbody a.establishment-link[data-turbo-frame=?]", "_top"
    assert_select "tbody a.link.font-mono[data-turbo-frame=?]", "_top"
  end

  # O cliente é o CNPJ e o EC é o grão técnico: quem abre um EC precisa ver os irmãos. Os
  # ECs 30000001 e 90000001 dividem o CNPJ na planilha sintética.
  test "a ficha lista todos os ECs do mesmo CNPJ, com link para os outros" do
    import_synthetic_workbook
    establishment = Establishment.find_by!(ec: "30000001")
    irmao = Establishment.find_by!(ec: "90000001")

    get establishment_path(establishment)

    assert_response :success
    assert_select "h2.table-title", text: "2 ECs deste cliente"
    assert_select "tbody th[scope=row]", text: /30000001/
    assert_select "tbody a.establishment-link[href=?]", establishment_path(irmao)
    # O EC aberto não vira link para si mesmo, e se anuncia.
    assert_select "tbody th[scope=row]", text: /nesta tela/
  end

  test "cliente de um EC só mostra a própria ficha na lista, sem inventar irmãos" do
    import_synthetic_workbook
    sozinho = Establishment.find_by!(ec: "30000002")

    get establishment_path(sozinho)

    assert_select "h2.table-title", text: "1 EC deste cliente"
    assert_select "tbody tr", count: 1
  end
end
