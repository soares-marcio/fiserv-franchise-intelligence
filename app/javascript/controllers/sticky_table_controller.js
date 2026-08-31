import { Controller } from "@hotwired/stimulus"

// A barra de título da tabela fica fixa ao rolar, e o cabeçalho das colunas logo abaixo
// dela. A altura da barra varia por página (título de uma ou duas linhas), então é medida.
export default class extends Controller {
  connect() {
    const toolbar = this.element.querySelector(".table-toolbar")
    if (!toolbar) return

    const update = () => this.element.style.setProperty("--toolbar-height", `${toolbar.offsetHeight}px`)
    update()
    this.observer = new ResizeObserver(update)
    this.observer.observe(toolbar)
  }

  disconnect() {
    this.observer?.disconnect()
  }
}
