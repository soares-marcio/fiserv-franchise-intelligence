import { Controller } from "@hotwired/stimulus"

// O <details> sozinho só fecha pelo próprio summary. Menu suspenso fecha também por Escape
// e por clique fora, e é isso que a pessoa tenta primeiro.
export default class extends Controller {
  connect() {
    this.closeOnOutside = this.closeOnOutside.bind(this)
    this.closeOnEscape = this.closeOnEscape.bind(this)
    this.close = this.close.bind(this)
    // Sem isto a página guardada pelo Turbo volta com o menu aberto no "voltar".
    document.addEventListener("turbo:before-cache", this.close)
  }

  disconnect() {
    this.stopListening()
    document.removeEventListener("turbo:before-cache", this.close)
  }

  toggle() {
    if (this.element.open) {
      document.addEventListener("click", this.closeOnOutside)
      document.addEventListener("keydown", this.closeOnEscape)
    } else {
      this.stopListening()
    }
  }

  close() {
    this.element.open = false
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEscape(event) {
    if (event.key !== "Escape") return

    this.close()
    this.element.querySelector("summary").focus()
  }

  stopListening() {
    document.removeEventListener("click", this.closeOnOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
  }
}
