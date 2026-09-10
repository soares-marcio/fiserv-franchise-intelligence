import { Controller } from "@hotwired/stimulus"

// A barra de contexto e o cabeçalho das colunas ficam empilhados ao rolar. As alturas variam
// por página, então são medidas para que uma camada não encubra a outra.
export default class extends Controller {
  connect() {
    const toolbar = this.element.querySelector(".table-toolbar")
    if (!toolbar) return

    const tabs = this.element.previousElementSibling?.matches(".variation-tabs-wrap")
      ? this.element.previousElementSibling
      : null

    const update = () => {
      this.element.style.setProperty("--toolbar-height", `${toolbar.offsetHeight}px`)
      this.element.style.setProperty("--variation-tabs-height", `${tabs?.offsetHeight || 0}px`)
    }
    update()
    this.observer = new ResizeObserver(update)
    this.observer.observe(toolbar)
    if (tabs) this.observer.observe(tabs)
  }

  disconnect() {
    this.observer?.disconnect()
  }
}
