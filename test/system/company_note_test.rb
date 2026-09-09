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

    find("tr.daily-row", text: "30000001").find("button.note-trigger").click

    # O formulário chega pelo frame, não pronto na página.
    assert_selector "dialog[open] trix-editor"
    find("dialog[open] trix-editor").click.send_keys("Dono viaja, retomar dia 10.")
    click_button "Salvar anotação"

    # O diálogo fecha no submit — sem isso, o morph do retorno o deixaria dessincronizado.
    assert_no_selector "dialog[open]"
    assert_text "Anotação salva."
    # E a busca que estava aplicada continua aplicada.
    assert_current_path(/q=ALFA\+LANCHES/, url: true)
    assert_equal "Dono viaja, retomar dia 10.",
      CompanyNote.find_by(cnpj: "11222333000181").body.to_plain_text
  end

  # Reabrir precisa trazer o que foi salvo, não o formulário como ele estava: é por isso que o
  # controller troca o src do frame a cada abertura.
  test "reabrir a anotação mostra o que foi salvo" do
    Operations::SaveCompanyNote.call(cnpj: "11222333000181", body: "<div>Escrito antes.</div>")

    visit sub_channel_report_path(@sub_channel)
    find("tr.daily-row", text: "30000001").find("button.note-trigger").click

    assert_selector "dialog[open] trix-editor", text: "Escrito antes."
  end

  # Esvaziar e salvar é o gesto de apagar — não há botão de excluir na tela.
  test "esvaziar o editor apaga a anotação" do
    Operations::SaveCompanyNote.call(cnpj: "11222333000181", body: "<div>Para apagar.</div>")

    visit sub_channel_report_path(@sub_channel)
    find("tr.daily-row", text: "30000001").find("button.note-trigger").click
    editor = find("dialog[open] trix-editor")
    editor.click
    editor.send_keys([ :control, "a" ], :backspace)
    click_button "Salvar anotação"

    assert_text "Anotação removida."
    assert_nil CompanyNote.find_by(cnpj: "11222333000181")
  end
end
