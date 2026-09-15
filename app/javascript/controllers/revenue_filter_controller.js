import { Controller } from "@hotwired/stimulus"

// Pílula do filtro de faturamento: o gatilho diz o recorte por extenso e o painel guarda a
// competência e a alça. Sem JavaScript o painel fica aberto e os dois campos continuam
// funcionando — são campos comuns, e o formulário os envia igual.
export default class extends Controller {
  static targets = ["trigger", "panel", "basis", "input", "value", "summary"]

  connect() {
    // Mesmo formato do helper brl do servidor: sem isso o rótulo troca de cara quando o
    // JavaScript carrega, de "R$ 5.000,00" para "R$ 5.000".
    this.formato = new Intl.NumberFormat("pt-BR", {
      style: "currency", currency: "BRL", minimumFractionDigits: 2
    })
    this.boundClose = this.closeOnOutside.bind(this)
    this.boundKey = this.closeOnEscape.bind(this)
    document.addEventListener("click", this.boundClose)
    document.addEventListener("keydown", this.boundKey)
    this.sync()
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
    document.removeEventListener("keydown", this.boundKey)
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.triggerTarget.classList.add("is-open")
    this.basisTarget.focus()
  }

  close(restoreFocus = false) {
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.classList.remove("is-open")
    if (restoreFocus) this.triggerTarget.focus()
  }

  // Quem liga e desliga o filtro é a competência: "Todas" é o estado desligado, e aí a alça
  // fica apagada e o gatilho diz "qualquer" em vez de um valor que não vale nada.
  sync() {
    const base = this.basisTarget
    const ligado = base.value !== ""
    const valor = this.formato.format(Number(this.inputTarget.value))
    this.inputTarget.disabled = !ligado
    this.valueTarget.textContent = ligado ? valor : "sem filtro"
    const rotulo = base.options[base.selectedIndex].text.toLowerCase()
    this.summaryTarget.textContent = ligado ? `${rotulo} até ${valor}` : "qualquer"
    this.summaryTarget.classList.toggle("filter-pill__value--empty", !ligado)
  }

  closeOnOutside(event) {
    if (!event.target.isConnected || this.element.contains(event.target)) return

    this.close()
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && !this.panelTarget.hidden) {
      event.preventDefault()
      this.close(true)
    }
  }
}
