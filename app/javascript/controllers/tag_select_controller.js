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
    this.chipsTarget.innerHTML = selected.map((box) => this.chipHtml(box)).join("")
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

  chipHtml(box) {
    const value = box.value
    const label = box.dataset.label || value
    const tone = box.dataset.tone || "neutral"
    return `<span class="status-tag" data-tone="${this.escape(tone)}">
      <span>${this.escape(label)}</span>
      <button type="button" class="status-tag__remove" data-tag-select-remove
        data-action="click->tag-select#remove" data-value="${this.escape(value)}"
        aria-label="Remover ${this.escape(label)}">×</button>
    </span>`
  }

  escape(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
  }
}
