import { Controller } from "@hotwired/stimulus"

// Pílula do filtro de faturamento: o gatilho resume o recorte e o painel guarda a competência
// e as duas alças.
//
// A alça carrega o **índice da parada**, não o valor. As paradas vêm do servidor
// (EstablishmentListingQuery::REVENUE_STOPS) e são espaçadas de propósito — R$ 1.000 até
// 30 mil, R$ 10.000 até 100 mil, R$ 50.000 até 300 mil, R$ 100.000 até 1 milhão —, porque a
// carteira não se distribui pela escala. Quem o formulário envia é o campo escondido, em reais.
export default class extends Controller {
  static targets = [
    "trigger", "panel", "basis", "min", "max", "minValue", "maxValue", "band", "value", "summary"
  ]
  static values = { stops: Array }

  connect() {
    // Tudo o que o filtro escreve vai sem centavos: as paradas são redondas, então os
    // centavos são sempre zero e só ocupam largura. Vale para o gatilho, para o painel e
    // para o que o leitor de tela anuncia — a mesma regra do brl_round do servidor.
    this.compact = new Intl.NumberFormat("pt-BR", {
      style: "currency", currency: "BRL", maximumFractionDigits: 0
    })
    this.number = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 })
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

  // Quem liga e desliga o filtro é a competência: "Todas" é o estado desligado, e aí as alças
  // ficam apagadas e o gatilho diz "qualquer" em vez de uma faixa que não vale nada.
  sync(event) {
    this.clamp(event?.target)
    const base = this.basisTarget
    const enabled = base.value !== ""
    const floor = this.money(this.minTarget)
    const ceiling = this.money(this.maxTarget)

    this.minTarget.disabled = !enabled
    this.maxTarget.disabled = !enabled
    this.minValueTarget.value = floor
    this.maxValueTarget.value = ceiling
    this.paintBand()
    this.describe(this.minTarget, floor)
    this.describe(this.maxTarget, ceiling)

    this.valueTarget.textContent = enabled
      ? `${this.compact.format(floor)} a ${this.compact.format(ceiling)}`
      : "sem filtro"

    // Mesma regra do helper revenue_summary: o piso só aparece quando corta, e o segundo
    // "R$" vira um traço — o texto por extenso não cabe no gatilho.
    const label = base.options[base.selectedIndex].text.toLowerCase()
    const band = floor > 0
      ? `${this.compact.format(floor)}–${this.number.format(ceiling)}`
      : `até ${this.compact.format(ceiling)}`
    this.summaryTarget.textContent = enabled ? `${label} · ${band}` : "qualquer"
    this.summaryTarget.classList.toggle("filter-pill__value--empty", !enabled)
  }

  money(handle) {
    return this.stopsValue[Number(handle.value)] ?? 0
  }

  // A alça anuncia a posição; o leitor de tela precisa ouvir o dinheiro.
  describe(handle, value) {
    handle.setAttribute("aria-valuetext", this.compact.format(value))
  }

  // As alças não se atravessam: a que está andando para no valor da outra. A que manda é a
  // que o usuário moveu — por isso o alvo do evento importa, e o sync do connect não clampeia.
  clamp(origin) {
    const floor = Number(this.minTarget.value)
    const ceiling = Number(this.maxTarget.value)
    if (floor <= ceiling) return this.stack(floor, ceiling)

    if (origin === this.minTarget) this.minTarget.value = ceiling
    else if (origin === this.maxTarget) this.maxTarget.value = floor
    this.stack(Number(this.minTarget.value), Number(this.maxTarget.value))
  }

  // Alças no mesmo ponto se cobrem, e só a de cima recebe o clique. A de cima tem que ser a
  // que ainda tem para onde ir: no topo da escala é o piso (o teto já não sobe), no resto é o
  // teto. Sem isso, as duas juntas no fim da escala travam o controle.
  stack(floor, ceiling) {
    const topBound = floor === ceiling && floor === Number(this.maxTarget.max)
    this.minTarget.style.zIndex = topBound ? "2" : "1"
    this.maxTarget.style.zIndex = topBound ? "1" : "2"
  }

  // A faixa acesa acompanha a posição da alça, e não o valor: é o índice que diz onde a alça
  // está no trilho.
  paintBand() {
    const scale = Number(this.maxTarget.max) || 1
    const floor = Number(this.minTarget.value)
    const ceiling = Number(this.maxTarget.value)
    this.bandTarget.style.left = `${(floor / scale) * 100}%`
    this.bandTarget.style.width = `${((ceiling - floor) / scale) * 100}%`
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
