import { Controller } from "@hotwired/stimulus"

// Modal dos lançamentos diários de um EC. O conteúdo chega por Turbo Frame; daqui sai só a
// abertura e o fechamento. É <dialog> nativo de propósito: showModal() já prende o foco e
// fecha no Esc, o que a busca global precisou escrever à mão.
export default class extends Controller {
  static targets = ["dialog"]

  // Só abre: o conteúdo é responsabilidade do Turbo. Mexer no innerHTML aqui apagaria o
  // <turbo-frame> alvo, e o Turbo, sem achar o frame, trocava a página inteira.
  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  // Clique em qualquer lugar da linha vale pelo link do EC. Cliques em links e botões da
  // própria linha seguem o caminho deles.
  openFromRow(event) {
    if (event.target.closest("a, button")) return

    event.currentTarget.querySelector(".daily-trigger")?.click()
  }

  close() {
    this.dialogTarget.close()
  }

  // Clique fora do conteúdo fecha: no <dialog>, o alvo é o próprio elemento.
  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
