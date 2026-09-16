import { Controller } from "@hotwired/stimulus"

// Pílula do filtro de faturamento: o gatilho resume o recorte e o painel guarda a competência,
// as duas alças e os dois campos digitáveis. Sem JavaScript o painel fica aberto e as alças
// continuam funcionando — são campos comuns, e o formulário os envia igual.
export default class extends Controller {
  static targets = [
    "trigger", "panel", "basis", "min", "max", "minField", "maxField", "band", "summary"
  ]

  connect() {
    // O resumo do gatilho vai sem centavos, como o helper revenue_summary: o passo do slider
    // é de R$ 1.000, então os centavos são sempre zero e só ocupam a largura que falta.
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

  // Alça movida (ou competência trocada): os campos acompanham.
  sync(event) {
    this.clamp(event?.target)
    this.mirrorFields()
    this.render()
  }

  // Campo digitado: a alça acompanha, mas o texto fica como o usuário escreveu. Normalizar a
  // cada tecla brigaria com quem digita — "12000" passa por "1", que o passo arredondaria
  // para zero antes do segundo algarismo.
  typed(event) {
    const campo = event.target
    const valor = Number(campo.value)
    if (campo.value === "" || Number.isNaN(valor)) return

    const alca = campo === this.minFieldTarget ? this.minTarget : this.maxTarget
    alca.value = Math.min(Math.max(valor, 0), Number(alca.max))
    this.clamp(alca)
    this.render()
  }

  // Ao sair do campo ele passa a mostrar o valor que a alça de fato assumiu, preso ao passo.
  settle() {
    this.mirrorFields()
    this.render()
  }

  // Quem liga e desliga o filtro é a competência: "Todas" é o estado desligado, e aí os
  // controles ficam apagados e o gatilho diz "qualquer" em vez de uma faixa que não vale nada.
  render() {
    const base = this.basisTarget
    const ligado = base.value !== ""
    const piso = Number(this.minTarget.value)
    const teto = Number(this.maxTarget.value)

    for (const campo of [this.minTarget, this.maxTarget, this.minFieldTarget, this.maxFieldTarget]) {
      campo.disabled = !ligado
    }
    this.paintBand(piso, teto)

    // Mesma regra do helper revenue_summary: o piso só aparece quando corta, e o segundo
    // "R$" vira um traço — o texto por extenso não cabe no gatilho.
    const rotulo = base.options[base.selectedIndex].text.toLowerCase()
    const faixa = piso > 0
      ? `${this.compacto.format(piso)}–${this.numero.format(teto)}`
      : `até ${this.compacto.format(teto)}`
    this.summaryTarget.textContent = ligado ? `${rotulo} · ${faixa}` : "qualquer"
    this.summaryTarget.classList.toggle("filter-pill__value--empty", !ligado)
  }

  mirrorFields() {
    this.minFieldTarget.value = this.minTarget.value
    this.maxFieldTarget.value = this.maxTarget.value
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

  paintBand(piso, teto) {
    const escala = Number(this.maxTarget.max) || 1
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
