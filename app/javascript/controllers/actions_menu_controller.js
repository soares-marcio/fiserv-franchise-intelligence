import { Controller } from "@hotwired/stimulus"

// O menu de ações da linha abre para fora da tabela, e a tabela o corta: `.table-scroll` tem
// `overflow-x: auto` para rolar na horizontal, e overflow declarado num eixo torna o outro
// `auto` também — não há como pedir só o horizontal. Medido no menu da última linha: dos
// 100px do painel, 57 ficavam fora do recorte.
//
// `position: fixed` escapa do recorte, mas o painel deixa de andar junto com o gatilho: a
// posição passa a ser calculada aqui, na abertura e a cada rolagem. Sem JavaScript o menu
// continua `absolute`, como era — cortado, e não quebrado.
export default class extends Controller {
  static targets = ["list"]

  connect() {
    this.reposition = this.reposition.bind(this)
  }

  disconnect() {
    this.stopFollowing()
  }

  toggle() {
    if (!this.element.open) return this.release()

    this.reposition()
    // Duas inscrições, e as duas fazem falta: a de captura pega a rolagem do `.table-scroll`
    // (evento de elemento não borbulha), e a comum pega a da página. Medido com uma só, em
    // captura: rolar a tabela reposicionava, rolar a página deixava o painel para trás.
    window.addEventListener("scroll", this.reposition, true)
    window.addEventListener("scroll", this.reposition)
    window.addEventListener("resize", this.reposition)
  }

  // Abre para baixo; sem espaço até o fim da janela, abre para cima do gatilho.
  reposition() {
    const trigger = this.element.querySelector("summary").getBoundingClientRect()
    const viewport = document.documentElement
    const list = this.listTarget
    list.style.position = "fixed"
    // Ancorado pela direita, não pela esquerda: com `left`, a caixa encolhe para caber no
    // que sobra até a borda e sai do alinhamento — medido, 11px fora. E clientWidth, não
    // innerWidth: o bloco que contém um `fixed` exclui a barra de rolagem.
    list.style.left = "auto"
    list.style.right = `${Math.max(8, viewport.clientWidth - trigger.right)}px`
    const height = list.offsetHeight
    const room = viewport.clientHeight - trigger.bottom
    const above = room < height + 12 && trigger.top > height + 12
    list.style.top = `${above ? trigger.top - height - 6 : trigger.bottom + 6}px`
  }

  stopFollowing() {
    window.removeEventListener("scroll", this.reposition, true)
    window.removeEventListener("scroll", this.reposition)
    window.removeEventListener("resize", this.reposition)
  }

  // Fechado, o painel volta ao posicionamento da folha de estilo: assim uma reabertura sem
  // JavaScript não herda coordenadas velhas.
  release() {
    this.stopFollowing()
    const list = this.listTarget
    list.style.position = ""
    list.style.left = ""
    list.style.top = ""
    list.style.right = ""
  }
}
