import { Controller } from "@hotwired/stimulus"

// O teto do filtro de faturamento enquanto a alça anda. Sem JavaScript o slider continua
// funcionando — ele é um input comum e o formulário o envia igual —, só não mostra o valor
// antes de aplicar.
export default class extends Controller {
  static targets = ["input", "value"]

  connect() {
    // Mesmo formato do helper brl do servidor: sem isso o rótulo troca de cara quando o
    // JavaScript carrega, de "R$ 5.000,00" para "R$ 5.000".
    this.formato = new Intl.NumberFormat("pt-BR", {
      style: "currency", currency: "BRL", minimumFractionDigits: 2
    })
    this.sync()
  }

  // No topo da escala não há teto: é assim que a tela abre, e é o que a consulta entende.
  sync() {
    const valor = Number(this.inputTarget.value)
    const teto = Number(this.inputTarget.max)
    this.valueTarget.textContent = valor >= teto ? "sem teto" : this.formato.format(valor)
  }
}
