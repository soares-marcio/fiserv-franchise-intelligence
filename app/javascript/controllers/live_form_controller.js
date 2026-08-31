import { Controller } from "@hotwired/stimulus"

// Submete o formulário sozinho enquanto o usuário digita, com uma pausa para não
// consultar a cada tecla. O botão continua funcionando sem JavaScript.
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  connect() {
    this.boundSync = this.syncFromFrame.bind(this)
    document.addEventListener("turbo:frame-load", this.boundSync)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.boundSync)
    clearTimeout(this.timer)
  }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  // Links dentro do frame (página, tamanho) mudam a URL sem passar pelo formulário;
  // os campos ocultos precisam acompanhar para a próxima digitação não os perder.
  syncFromFrame(event) {
    const frame = event.target
    if (frame.id !== this.element.dataset.turboFrame || !frame.src) return

    const params = new URL(frame.src).searchParams
    this.element.querySelectorAll("input[type=hidden]").forEach((input) => {
      if (params.has(input.name)) input.value = params.get(input.name)
    })
  }
}
