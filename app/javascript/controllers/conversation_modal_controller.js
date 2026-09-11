import { Controller } from "@hotwired/stimulus"

// Modal da melhor conversa de um cliente. Diferente do modal de lançamentos, o conteúdo já
// veio na linha: não há Turbo Frame nem ida ao servidor, o botão carrega as conversas e o
// nome.
export default class extends Controller {
  static targets = ["dialog", "name", "groups"]

  open({ params: { items, name } }) {
    this.nameTarget.textContent = name || ""
    this.render(Array.isArray(items) ? items : [])
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  // Um bloco por EC: a conversa é de cada ponto de venda, e 116 dos 302 clientes da carteira
  // têm mais de um texto diferente. Juntar tudo numa lista só inventaria uma sequência de
  // ações que ninguém escreveu. Com uma conversa só, o rótulo do EC não aparece — não há o
  // que distinguir.
  render(items) {
    this.groupsTarget.replaceChildren()
    const rotular = items.length > 1
    items.forEach(({ ec, text }) => {
      const group = document.createElement("div")
      if (rotular) group.appendChild(this.label(ec))
      group.appendChild(this.steps(text || ""))
      this.groupsTarget.appendChild(group)
    })
  }

  // createElement + textContent, nunca innerHTML: tanto o número do EC quanto o texto são da
  // planilha do cliente e entram aqui sem passar por sanitização.
  label(ec) {
    const label = document.createElement("p")
    label.className = "section-label conversation-groups__ec"
    label.textContent = `EC ${ec}`
    return label
  }

  // O separador ">" é o da planilha: BinImport::Template declara "split_actions(>)" para a
  // coluna MELHOR CONVERSA, e o importador quebra por ele ao gravar as ações. Texto sem
  // separador vira um item só.
  steps(text) {
    const list = document.createElement("ol")
    list.className = "conversation-steps"
    text
      .split(">")
      .map((step) => step.trim())
      .filter((step) => step.length > 0)
      .forEach((step) => {
        const item = document.createElement("li")
        item.textContent = step
        list.appendChild(item)
      })
    return list
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
