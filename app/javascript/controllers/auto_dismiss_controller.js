import { Controller } from "@hotwired/stimulus"

// Some com o aviso depois de um tempo. Existe porque a anotação passou a salvar sem recarregar
// a página: sem a navegação para limpar o flash, ele ficaria na tela até a próxima.
export default class extends Controller {
  static values = { after: Number }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.afterValue || 5000)
  }

  // O Turbo pode remover o elemento antes da hora — ao trocar o flash por outro, por exemplo.
  // Sem limpar, o timer dispararia sobre um nó que já saiu do documento.
  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.classList.add("is-leaving")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
    // Se a transição não acontecer (motion reduzido, aba em segundo plano), o aviso sai assim
    // mesmo — o timer é a garantia, a animação é o enfeite.
    setTimeout(() => this.element.remove(), 400)
  }
}
