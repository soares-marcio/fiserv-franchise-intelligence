import { Controller } from "@hotwired/stimulus"

// O teto do filtro de faturamento enquanto a alça anda, e o estado ligado/desligado do
// conjunto. Quem liga é a base — "Todas" é o desligado —, então sem base escolhida a alça
// fica apagada e o rótulo diz "sem filtro" em vez de um valor que não vale nada.
//
// Sem JavaScript os dois campos continuam funcionando: são campos comuns e o formulário os
// envia igual. O que o controller faz é só mostrar o estado antes de aplicar.
export default class extends Controller {
  static targets = ["input", "value", "basis"]

  connect() {
    // Mesmo formato do helper brl do servidor: sem isso o rótulo troca de cara quando o
    // JavaScript carrega, de "R$ 5.000,00" para "R$ 5.000".
    this.formato = new Intl.NumberFormat("pt-BR", {
      style: "currency", currency: "BRL", minimumFractionDigits: 2
    })
    this.sync()
  }

  sync() {
    const ligado = this.basisTarget.value !== ""
    this.inputTarget.disabled = !ligado
    this.inputTarget.closest(".revenue-range").classList.toggle("is-off", !ligado)
    this.valueTarget.textContent = ligado
      ? this.formato.format(Number(this.inputTarget.value))
      : "sem filtro"
  }
}
