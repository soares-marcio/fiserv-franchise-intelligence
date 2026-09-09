import { Controller } from "@hotwired/stimulus"

// Modal da melhor conversa de um EC. Diferente do modal de lançamentos, o conteúdo já veio
// na linha: não há Turbo Frame nem ida ao servidor, o botão carrega o texto e o nome.
export default class extends Controller {
  static targets = ["dialog", "name", "steps"]

  open({ params: { text, name } }) {
    this.nameTarget.textContent = name || ""
    this.render(text || "")
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  // O separador ">" é o da planilha: BinImport::Template declara "split_actions(>)" para a
  // coluna MELHOR CONVERSA, e o importador quebra por ele ao gravar as ações. Texto sem
  // separador vira um item só.
  //
  // createElement + textContent, nunca innerHTML: o texto é da planilha do cliente e entra
  // aqui sem passar por sanitização.
  render(text) {
    this.stepsTarget.replaceChildren()
    text
      .split(">")
      .map((step) => step.trim())
      .filter((step) => step.length > 0)
      .forEach((step) => {
        const item = document.createElement("li")
        item.textContent = step
        this.stepsTarget.appendChild(item)
      })
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
