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
  end

  test "clicar no chip do EC abre a ficha daquele EC" do
    visit establishments_path

    find("a.link.font-mono", text: "EC 90000001").click

    assert_selector "h1", text: "ALFA EXPRESS"
    assert_no_text "Content missing"
  end
end
