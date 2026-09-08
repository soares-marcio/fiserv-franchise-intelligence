import { Controller } from "@hotwired/stimulus"

// Copia o relato da falha para a área de transferência. O portal é servido em HTTP, onde
// navigator.clipboard não existe: por isso a seleção do textarea com execCommand fica como
// caminho de volta, e o texto continua visível para a cópia manual se os dois falharem.
export default class extends Controller {
  static targets = ["source", "feedback"]

  async copy() {
    const texto = this.sourceTarget.value

    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(texto)
      } else {
        this.sourceTarget.select()
        if (!document.execCommand("copy")) throw new Error("execCommand recusou")
      }
      this.aviso("Relato copiado.")
    } catch {
      this.sourceTarget.select()
      this.aviso("Não consegui copiar sozinho. O texto está selecionado: use Cmd+C.")
    }
  }

  aviso(texto) {
    this.feedbackTarget.textContent = texto
    clearTimeout(this.timer)
    this.timer = setTimeout(() => (this.feedbackTarget.textContent = ""), 6000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
