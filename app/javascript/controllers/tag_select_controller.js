import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "chips", "placeholder", "menu"]

  connect() {
    this.sync()
    this.boundClose = this.closeOnOutside.bind(this)
    this.boundKey = this.closeOnEscape.bind(this)
    document.addEventListener("click", this.boundClose)
    document.addEventListener("keydown", this.boundKey)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
    document.removeEventListener("keydown", this.boundKey)
  }

  toggle(event) {
    if (event.target.closest("[data-tag-select-remove]")) return

    this.menuOpen() ? this.close() : this.open()
  }

  sync() {
    const selected = this.selectedBoxes()
    this.chipsTarget.replaceChildren(...selected.map((box) => this.chipElement(box)))
    this.placeholderTarget.hidden = selected.length > 0
    this.element.querySelectorAll(".tag-select__option").forEach((option) => {
      const checked = Boolean(option.querySelector("input")?.checked)
      option.classList.toggle("is-selected", checked)
      option.setAttribute("aria-selected", String(checked))
    })
  }

  remove(event) {
    event.preventDefault()
    event.stopPropagation()
    const value = event.currentTarget.dataset.value
    const box = this.boxes().find((input) => input.value === value)
    if (!box) return

    box.checked = false
    this.sync()
  }

  keydown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.open()
      return
    }
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.toggle(event)
    }
    if (event.key === "Backspace" && !this.menuOpen()) {
      const last = this.selectedBoxes().at(-1)
      if (!last) return

      last.checked = false
      this.sync()
    }
  }

  menuKeydown(event) {
    const boxes = this.boxes()
    const current = boxes.indexOf(event.target)
    let next
    if (event.key === "ArrowDown") next = boxes[current + 1] || boxes[0]
    else if (event.key === "ArrowUp") next = boxes[current - 1] || boxes.at(-1)
    else if (event.key === "Home") next = boxes[0]
    else if (event.key === "End") next = boxes.at(-1)
    else return

    event.preventDefault()
    next?.focus()
  }

  open() {
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.triggerTarget.classList.add("is-open")
    const firstOption = this.selectedBoxes()[0] || this.boxes()[0]
    firstOption?.focus()
  }

  close(restoreFocus = false) {
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.classList.remove("is-open")
    if (restoreFocus) this.triggerTarget.focus()
  }

  closeOnOutside(event) {
    if (!event.target.isConnected || this.element.contains(event.target)) return

    this.close()
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && this.menuOpen()) {
      event.preventDefault()
      this.close(true)
    }
  }

  menuOpen() {
    return !this.menuTarget.hidden
  }

  boxes() {
    return [...this.element.querySelectorAll("input[type='checkbox']")]
  }

  selectedBoxes() {
    return this.boxes().filter((input) => input.checked)
  }

  chipElement(box) {
    const value = box.value
    const label = box.dataset.label || value
    const tone = box.dataset.tone || "neutral"
    // Texto, e não caixinha: dentro da pílula o valor é a informação, e uma caixa com borda
    // dentro de outra caixa com borda vira ruído. O × fica discreto ao lado de cada valor.
    const chip = document.createElement("span")
    chip.className = "filter-pill__tag"
    chip.dataset.tone = tone

    const text = document.createElement("span")
    text.textContent = label

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "filter-pill__tag-remove"
    remove.dataset.tagSelectRemove = ""
    remove.dataset.action = "click->tag-select#remove"
    remove.dataset.value = value
    remove.setAttribute("aria-label", `Remover ${label}`)
    remove.textContent = "×"

    chip.append(text, remove)
    return chip
  }
}
