require "application_system_test_case"

# A listagem vive num turbo-frame e o cadastro do EC não tem esse frame: sem escapar para
# _top, o Turbo troca a listagem por "Content missing" e a tela fica em branco. Só o
# navegador prova — com curl o link responde 200 e parece são.
class EstablishmentsListingTest < ApplicationSystemTestCase
  setup do
    import_synthetic_workbook
    refresh_audit_views
  end

  test "clicar no nome do cliente abre a ficha do estabelecimento" do
    visit establishments_path

    find("a.establishment-link", match: :first).click

    assert_selector "h1", text: "ALFA LANCHES"
    assert_no_text "Content missing"
    assert_current_path(%r{/establishments/[0-9a-f-]{36}})
    # A ficha é do CNPJ: os dois ECs do cliente aparecem como blocos.
    assert_selector "#ec-30000001"
    assert_selector "#ec-90000001"
  end

  # O chip do EC cai na mesma ficha, na âncora daquele EC: o h1 não muda, então afirmar o
  # nome do EC passaria por engano. O que prova é o bloco existir no destino.
  test "clicar no chip do EC abre a ficha ancorada naquele EC" do
    visit establishments_path

    find("a.link.font-mono", text: "EC 90000001").click

    assert_no_text "Content missing"
    assert_current_path(/#ec-90000001/, url: true)
    assert_selector "#ec-90000001 .section-label", text: "EC 90000001"
  end
end
