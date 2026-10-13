import { Controller } from "@hotwired/stimulus"

// Recolhível só no telefone. No desktop o summary some, e um <details> fechado não
// renderiza os filhos — o CSS `display: block` não atravessa essa regra do HTML.
// Quem fecha no celular e alarga a janela ficaria sem filtros até recarregar.
export default class extends Controller {
  connect() {
    this.desktopMedia = window.matchMedia("(min-width: 768px)")
    this.boundViewportChange = (event) => {
      if (event.matches) this.element.open = true
    }
    this.desktopMedia.addEventListener("change", this.boundViewportChange)
    if (this.desktopMedia.matches) this.element.open = true
  }

  disconnect() {
    this.desktopMedia?.removeEventListener("change", this.boundViewportChange)
  }
}
