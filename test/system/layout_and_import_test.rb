require "application_system_test_case"

class LayoutAndImportTest < ApplicationSystemTestCase
  test "navega pela casca e abre a busca global" do
    visit import_batches_path

    assert_selector "nav[aria-label='Navegação principal']"
    assert_selector "nav[aria-label='Trilha de navegação']", text: "Importar arquivo"

    click_button "Buscar EC, CNPJ, nome ou MIC"
    assert_selector "[role='dialog']", visible: true
    assert_selector "input[aria-label='Buscar estabelecimentos e MICs']:focus"

    find("input[aria-label='Buscar estabelecimentos e MICs']").set("teste")
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

  # A mensagem de falha não tinha limite de largura: ela esticava a coluna de Status e
  # empurrava o botão "Descartar" para fora da área visível da tabela — medido na carteira
  # real, janela de 1600px, a tabela pedia 2947px num espaço de 1502px. O texto inteiro
  # continua na ficha do lote e no title; aqui ele fica em duas linhas.
  test "a mensagem de falha não empurra o botão de descartar para fora" do
    ImportBatch.create!(
      source_filename: "BIN_TESTE_20260903.xlsx", file_checksum: "abc123def456789",
      status: "failed",
      validation_errors: [
        "A aba \"Mapa de Clientes BIN\" está sem a coluna \"REPORT_ID\". No lugar apareceu " \
        "\"ELEGIBILIDADE\", e o importador lê as células pelo nome da coluna, então nenhuma " \
        "linha seria reconhecida."
      ]
    )

    visit import_batches_path
    assert_selector "tbody .import-error"

    medida = page.evaluate_script(<<~JS)
      (() => {
        const rolagem = document.querySelector(".table-scroll")
        const tabela = rolagem.querySelector("table")
        const mensagem = document.querySelector("tbody .import-error")
        const botao = document.querySelector("tbody td .btn")
        const linha = parseFloat(getComputedStyle(mensagem).lineHeight)
        return {
          sobra: Math.round(tabela.scrollWidth - rolagem.clientWidth),
          linhas: Math.round(mensagem.getBoundingClientRect().height / linha),
          botao_dentro: botao
            ? Math.round(botao.getBoundingClientRect().right) <= Math.round(rolagem.getBoundingClientRect().right) + 1
            : null,
          texto_completo: mensagem.getAttribute("title") || ""
        }
      })()
    JS

    assert_operator medida["sobra"], :<=, 0, "a tabela não pode transbordar por causa da mensagem"
    assert medida["botao_dentro"], "o botão Descartar precisa caber na área visível"
    assert_operator medida["linhas"], :<=, 2, "a mensagem fica em duas linhas"
    assert_includes medida["texto_completo"], "REPORT_ID",
      "o texto inteiro continua acessível no title"
  end

  # Voltou em 20/09/2026 com a carteira real: a mensagem já cabia, mas os nomes de arquivo de
  # 60 caracteres e o nome do Master, que não quebram linha, somavam mais que a área visível e o
  # botão de descartar saía do card de novo. O que o usuário vê é a tabela inteira, com o que a
  # Fiserv e o operador nomeiam do jeito que nomeiam.
  test "nomes longos de arquivo e de Master não empurram o botão de descartar para fora" do
    goias = Channel.create!(external_id: "1479", name: "MASTER FRANQUEADO REGIAO GOIAS")
    ramos = Channel.create!(external_id: "1478", name: "MASTER FRANQUEADO RAMOS E SILVA")
    ImportBatch.create!(
      channel: goias, source_filename: "14.09.26 - MCB 17 09.xlsx", file_checksum: "f" * 12,
      status: "failed", current_month_cutoff_day: 14,
      validation_errors: [
        "PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint " \
        "\"index_map_snapshots_on_import_batch_id_and_establishment_id\"\nDETAIL:  Key " \
        "(import_batch_id, establishment_id)=(20, 617) already exists."
      ]
    )
    7.times do |i|
      ImportBatch.create!(
        channel: ramos, status: "validated", current_month_cutoff_day: 14 - i,
        source_filename: "14.09.26 - 1478_MASTER FRANQUEADO RAMOS E SILV_2026091#{i}.xlsx",
        file_checksum: "a#{i}" * 6
      )
    end

    visit import_batches_path
    assert_selector "tbody .import-error"

    medida = page.evaluate_script(<<~JS)
      (() => {
        const rolagem = document.querySelector(".table-scroll")
        const tabela = rolagem.querySelector("table")
        const botao = document.querySelector("tbody td .btn")
        return {
          sobra: Math.round(tabela.scrollWidth - rolagem.clientWidth),
          botao_dentro: Math.round(botao.getBoundingClientRect().right) <= Math.round(rolagem.getBoundingClientRect().right) + 1
        }
      })()
    JS

    assert_operator medida["sobra"], :<=, 0, "a tabela não pode transbordar por causa dos nomes"
    assert medida["botao_dentro"], "o botão Descartar precisa caber na área visível"
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
