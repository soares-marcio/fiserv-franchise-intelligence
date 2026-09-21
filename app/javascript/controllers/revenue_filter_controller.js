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
    this.compacto = new Intl.NumberFormat("pt-BR", {
      style: "currency", currency: "BRL", maximumFractionDigits: 0
    })
    this.numero = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 })
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
    const ligado = base.value !== ""
    const piso = this.money(this.minTarget)
    const teto = this.money(this.maxTarget)

    this.minTarget.disabled = !ligado
    this.maxTarget.disabled = !ligado
    this.minValueTarget.value = piso
    this.maxValueTarget.value = teto
    this.paintBand()
    this.describe(this.minTarget, piso)
    this.describe(this.maxTarget, teto)

    this.valueTarget.textContent = ligado
      ? `${this.compacto.format(piso)} a ${this.compacto.format(teto)}`
      : "sem filtro"

    // Mesma regra do helper revenue_summary: o piso só aparece quando corta, e o segundo
    // "R$" vira um traço — o texto por extenso não cabe no gatilho.
    const rotulo = base.options[base.selectedIndex].text.toLowerCase()
    const faixa = piso > 0
      ? `${this.compacto.format(piso)}–${this.numero.format(teto)}`
      : `até ${this.compacto.format(teto)}`
    this.summaryTarget.textContent = ligado ? `${rotulo} · ${faixa}` : "qualquer"
    this.summaryTarget.classList.toggle("filter-pill__value--empty", !ligado)
  }

  money(alca) {
    return this.stopsValue[Number(alca.value)] ?? 0
  }

  // A alça anuncia a posição; o leitor de tela precisa ouvir o dinheiro.
  describe(alca, valor) {
    alca.setAttribute("aria-valuetext", this.compacto.format(valor))
  }

  // As alças não se atravessam: a que está andando para no valor da outra. A que manda é a
  // que o usuário moveu — por isso o alvo do evento importa, e o sync do connect não clampeia.
  clamp(origem) {
    const piso = Number(this.minTarget.value)
    const teto = Number(this.maxTarget.value)
    if (piso <= teto) return this.stack(piso, teto)

    if (origem === this.minTarget) this.minTarget.value = teto
    else if (origem === this.maxTarget) this.maxTarget.value = piso
    this.stack(Number(this.minTarget.value), Number(this.maxTarget.value))
  }

  // Alças no mesmo ponto se cobrem, e só a de cima recebe o clique. A de cima tem que ser a
  // que ainda tem para onde ir: no topo da escala é o piso (o teto já não sobe), no resto é o
  // teto. Sem isso, as duas juntas no fim da escala travam o controle.
  stack(piso, teto) {
    const topo = piso === teto && piso === Number(this.maxTarget.max)
    this.minTarget.style.zIndex = topo ? "2" : "1"
    this.maxTarget.style.zIndex = topo ? "1" : "2"
  }

  // A faixa acesa acompanha a posição da alça, e não o valor: é o índice que diz onde a alça
  // está no trilho.
  paintBand() {
    const escala = Number(this.maxTarget.max) || 1
    const piso = Number(this.minTarget.value)
    const teto = Number(this.maxTarget.value)
    this.bandTarget.style.left = `${(piso / escala) * 100}%`
    this.bandTarget.style.width = `${((teto - piso) / escala) * 100}%`
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
