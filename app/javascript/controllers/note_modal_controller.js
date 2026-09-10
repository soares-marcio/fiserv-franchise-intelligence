import { Controller } from "@hotwired/stimulus"

// Modal da anotação do cliente. Diferente do modal da melhor conversa, o conteúdo não vem no
// data-* do botão: é HTML com anexos, e vinte linhas de tabela carregariam vinte deles. O
// botão traz só o endereço, e o frame busca o formulário quando o diálogo abre.
export default class extends Controller {
  static targets = ["dialog", "frame"]

  open({ params: { url } }) {
    // Trocar o src refaz a requisição mesmo para o mesmo cliente — é o que traz de volta o
    // que foi salvo por último, em vez de reabrir o formulário como ele estava.
    this.frameTarget.src = url
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
