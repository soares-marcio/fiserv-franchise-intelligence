require "application_system_test_case"

# A anotação só existe de verdade no navegador: o editor é o Trix, o conteúdo do modal chega
# por Turbo Frame e o layout usa morph no retorno. Nada disso é exercitado por teste de
# controller — ali o servidor entrega o botão certo mesmo que o JavaScript nunca rode.
class CompanyNoteTest < ApplicationSystemTestCase
  setup do
    import_synthetic_workbook
    refresh_audit_views
    @sub_channel = SubChannel.find_by!(name: "MIC ALFA")
  end

  test "escreve a anotação pelo modal e ela volta na tela, sem perder o recorte" do
    visit sub_channel_report_path(@sub_channel, q: "ALFA LANCHES")

    abrir_anotacao("30000001")

    # O formulário chega pelo frame, não pronto na página.
    assert_selector "dialog[open] trix-editor"
    find("dialog[open] trix-editor").click.send_keys("Dono viaja, retomar dia 10.")
    click_button "Salvar anotação"

    assert_no_selector "dialog[open]"
    assert_text "Anotação salva."
    # O ponto aparece sem a página recarregar: é o turbo_stream trocando a célula, e o
    # gatilho do menu a lê com :has() — é ele que fica à vista com o menu fechado.
    assert_selector "td.actions-col .actions-menu:has(.note-trigger__dot)"
    # E a busca que estava aplicada continua aplicada.
    assert_current_path(/q=ALFA\+LANCHES/, url: true)
    assert_equal "Dono viaja, retomar dia 10.",
      CompanyNote.find_by(cnpj: "11222333000181").body.to_plain_text
  end

  # O aviso some sozinho. Antes, quem fechava o flash era a navegação seguinte — e agora não
  # há navegação nenhuma depois de salvar.
  test "o aviso de sucesso desaparece sozinho" do
    visit sub_channel_report_path(@sub_channel)
    abrir_anotacao("30000001")
    find("dialog[open] trix-editor").click.send_keys("Nota rápida.")
    click_button "Salvar anotação"

    assert_text "Anotação salva."
    assert_no_text "Anotação salva.", wait: 10
  end

  # O CNPJ com dois ECs tem duas linhas na listagem, e as duas mostram a mesma anotação. Com
  # alvo por id, só a primeira mudaria depois de salvar; com seletor, as duas mudam.
  test "salvar atualiza todas as linhas do mesmo cliente de uma vez" do
    visit sub_channel_report_path(@sub_channel)

    assert_no_selector ".note-trigger__dot", visible: :all
    abrir_anotacao("30000001")
    find("dialog[open] trix-editor").click.send_keys("Vale para os dois ECs.")
    click_button "Salvar anotação"

    assert_text "Anotação salva."
    assert_selector "td.actions-col .actions-menu:has(.note-trigger__dot)", count: 2
  end

  # Reabrir precisa trazer o que foi salvo, não o formulário como ele estava: é por isso que o
  # controller troca o src do frame a cada abertura.
  test "reabrir a anotação mostra o que foi salvo" do
    Operations::SaveCompanyNote.call(cnpj: "11222333000181", body: "<div>Escrito antes.</div>")

    visit sub_channel_report_path(@sub_channel)
    abrir_anotacao("30000001")

    assert_selector "dialog[open] trix-editor", text: "Escrito antes."
  end

  # Esvaziar e salvar é o gesto de apagar — não há botão de excluir na tela.
  test "esvaziar o editor apaga a anotação" do
    Operations::SaveCompanyNote.call(cnpj: "11222333000181", body: "<div>Para apagar.</div>")

    visit sub_channel_report_path(@sub_channel)
    abrir_anotacao("30000001")
    editor = find("dialog[open] trix-editor")
    editor.click
    editor.send_keys([ :control, "a" ], :backspace)
    click_button "Salvar anotação"

    assert_text "Anotação removida."
    assert_nil CompanyNote.find_by(cnpj: "11222333000181")
  end

  private

  # O botão da anotação vive no menu de ações da linha, fechado até o clique no gatilho.
  def abrir_anotacao(ec)
    linha = find("tr.daily-row", text: ec)
    linha.find("summary.actions-menu__trigger").click
    linha.find("button.note-trigger").click
  end
end
