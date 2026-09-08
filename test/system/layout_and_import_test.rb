require "application_system_test_case"

class LayoutAndImportTest < ApplicationSystemTestCase
  test "navega pela casca e abre a busca global" do
    visit import_batches_path

    assert_selector "nav[aria-label='Navegação principal']"
    assert_selector "nav[aria-label='Trilha de navegação']", text: "Importar arquivo"

    click_button "Buscar EC, CNPJ, nome ou subcanal"
    assert_selector "[role='dialog']", visible: true
    assert_selector "input[aria-label='Buscar estabelecimentos e subcanais']:focus"

    find("input[aria-label='Buscar estabelecimentos e subcanais']").set("teste")
    assert_text "A carteira ainda não tem arquivo importado"

    find("body").send_keys(:escape)
    assert_no_selector "[role='dialog']", visible: true
  end

  test "envia uma planilha pela interface e mostra o lote pendente" do
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-BIN_TESTE_20260811.xlsx")
    BinWorkbook.write(path)

    visit import_batches_path
    attach_file "Arquivo XLSX", path
    accept_confirm { click_button "Iniciar importação" }

    assert_text "Importação enfileirada."
    assert_text path.basename.to_s
    assert_text "Importando"
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  # A tabela de sete colunas dentro do card vazava por cima do card vizinho: no desktop o
  # .table-scroll geral é overflow: visible, e o item de grid sem min-width: 0 esticava a
  # coluna inteira. O card tem que conter a própria tabela, rolando por dentro.
  test "os cards do recorrente contêm a tabela em vez de vazar" do
    import_synthetic_workbook(lojas: BinWorkbook.earnings_lojas)
    refresh_audit_views

    visit recurring_reports_path
    assert_selector "article.earnings-card"

    vazamento = page.evaluate_script(<<~JS)
      (() => {
        const cards = [...document.querySelectorAll("article.earnings-card")]
        return cards.filter((card) => card.scrollWidth > card.clientWidth + 1).length
      })()
    JS

    assert_equal 0, vazamento, "nenhum card pode transbordar o próprio limite"
  end
end
