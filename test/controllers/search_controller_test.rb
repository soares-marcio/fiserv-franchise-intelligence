require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "sem consulta mostra o que dá para buscar" do
    get search_path

    assert_response :success
    assert_select "turbo-frame#global-search p.search-hint", text: /EC, CNPJ, nome, cidade, CNAE ou subcanal/
  end

  test "encontra subcanal e os estabelecimentos dele" do
    import_synthetic_workbook
    sub_channel = SubChannel.find_by!(name: "MIC ALFA")

    get search_path(q: "mic alfa")

    assert_select ".search-group h3", text: "Subcanais"
    assert_select "a.search-result[href=?]", sub_channel_report_path(sub_channel), text: /MIC ALFA/
    assert_select ".search-group h3", text: "Estabelecimentos"
    assert_select "a.search-result", text: /30000001/
    assert_select "a.search-more[href=?]", establishments_path(q: "mic alfa")
  end

  test "encontra estabelecimento por EC, CNPJ e nome" do
    import_synthetic_workbook
    beta = Establishment.find_by!(ec: "30000002")

    # O CNPJ formatado precisa achar igual: o banco guarda só dígitos, a limpeza é da busca.
    { "30000002" => "EC", "44555666" => "CNPJ", "beta cafe" => "nome",
      "44.555.666/0001-72" => "CNPJ formatado" }.each do |query, kind|
      get search_path(q: query)
      assert_select "a.search-result[href=?]", establishment_path(beta), { text: /BETA CAFE/ }, "por #{kind}"
    end
  end

  test "diz quando não acha nada" do
    import_synthetic_workbook
    get search_path(q: "zzz")

    assert_select "p.search-empty", text: /Nada encontrado para “zzz”/
  end

  test "sem arquivo importado aponta a importação em vez de dizer que não achou" do
    get search_path(q: "zzz")

    assert_select "p.search-empty", text: /ainda não tem arquivo importado/
    assert_select "p.search-empty a[href=?]", import_batches_path
    assert_select "p.search-empty", text: /Nada encontrado/, count: 0
  end

  test "requisição do frame vem sem a casca; acesso direto vem com ela" do
    get search_path(q: "zzz"), headers: { "Turbo-Frame" => "global-search" }
    assert_select "header.topbar", count: 0
    assert_select "turbo-frame#global-search"

    get search_path(q: "zzz")
    assert_select "header.topbar", count: 1
  end
end
