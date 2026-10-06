import { Controller } from "@hotwired/stimulus"

// Dependência entre permissões no convite, a mesma de Permission::REQUIRES. Base única
// (editar → ver anotação): marcar a dependente marca e trava a base; desmarcar destrava, e
// desmarca a base só se foi este controller que a marcou. Alternativas (ver anotação →
// Faturamento, Clover Capital ou Estabelecimentos): a dependente fica desabilitada até uma
// delas ser marcada. O estado inicial vem do servidor (UsersHelper), e caixa travada não
// viaja no formulário — quem completa a base ao salvar é Permission.with_implied.
export default class extends Controller {
  static targets = ["box"]

  toggle(event) {
    const box = event.target
    const bases = this.requires(box)
    if (bases.length === 1) {
      const base = this.find(bases[0])
      if (box.checked && base && !base.checked) {
        base.checked = true
        base.dataset.autoChecked = "true"
      } else if (!box.checked && base?.dataset.autoChecked) {
        base.checked = false
        delete base.dataset.autoChecked
      }
    }
    this.refresh()
  }

  refresh() {
    this.boxTargets.forEach((box) => {
      if (!this.available(box)) {
        box.checked = false
        box.disabled = true
      } else if (this.locked(box)) {
        box.checked = true
        box.disabled = true
      } else {
        box.disabled = false
      }
    })
  }

  available(box) {
    const bases = this.requires(box)
    if (bases.length === 0) return true
    if (bases.length === 1) {
      const base = this.find(bases[0])
      return !base || this.available(base)
    }
    return bases.some((key) => this.find(key)?.checked)
  }

  locked(box) {
    return this.boxTargets.some((other) =>
      other.checked && other !== box && this.singleBases(other).includes(box.dataset.key))
  }

  singleBases(box) {
    const bases = this.requires(box)
    if (bases.length !== 1) return []
    const base = this.find(bases[0])
    return [bases[0], ...(base ? this.singleBases(base) : [])]
  }

  requires(box) {
    return JSON.parse(box.dataset.requires || "[]")
  }

  find(key) {
    return this.boxTargets.find((box) => box.dataset.key === key)
  }
}
