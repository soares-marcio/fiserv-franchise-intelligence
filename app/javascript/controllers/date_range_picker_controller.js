import { Controller } from "@hotwired/stimulus"

const WEEKDAYS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
const MONTHS = [
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"
]

export default class extends Controller {
  static targets = [
    "panel", "grid", "monthLabel", "trigger", "triggerLabel", "hint", "fromDate", "toDate"
  ]
  static values = {
    fromDate: String,
    toDate: String
  }

  connect() {
    this.visible = this.initialMonth()
    this.picking = null
    this.render()
    this.boundClose = this.closeOnOutside.bind(this)
    this.boundKey = this.closeOnEscape.bind(this)
    document.addEventListener("click", this.boundClose)
    document.addEventListener("keydown", this.boundKey)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
    document.removeEventListener("keydown", this.boundKey)
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  prevMonth(event) {
    event.preventDefault()
    this.shiftMonth(-1)
  }

  nextMonth(event) {
    event.preventDefault()
    this.shiftMonth(1)
  }

  pick(event) {
    const day = Number(event.target.closest("[data-day]")?.dataset.day)
    if (!day) return

    const iso = this.isoDate(this.visible, day)
    if (this.picking == null) {
      this.picking = iso
      this.fromDateValue = iso
      this.toDateValue = iso
    } else {
      this.fromDateValue = this.picking <= iso ? this.picking : iso
      this.toDateValue = this.picking <= iso ? iso : this.picking
      this.picking = null
    }

    this.syncFields()
    this.updateLabels()
    this.applyRangeClasses()
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.triggerTarget.classList.add("is-open")
    const preferred = this.gridTarget.querySelector(".is-start, .is-today, button[data-day]")
    preferred?.focus()
  }

  close(restoreFocus = false) {
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.classList.remove("is-open")
    this.picking = null
    if (restoreFocus) this.triggerTarget.focus()
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

  shiftMonth(delta) {
    this.visible = new Date(this.visible.getFullYear(), this.visible.getMonth() + delta, 1)
    this.monthLabelTarget.textContent = this.monthTitle()
    this.renderGrid()
  }

  clear(event) {
    event.preventDefault()
    this.picking = null
    this.fromDateValue = ""
    this.toDateValue = ""
    this.syncFields()
    this.updateLabels()
    this.applyRangeClasses()
  }

  finish(event) {
    event.preventDefault()
    this.close(true)
  }

  navigate(event) {
    const offsets = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }
    if (!(event.key in offsets)) return

    const buttons = [...this.gridTarget.querySelectorAll("button[data-day]")]
    const current = buttons.indexOf(event.target.closest("button[data-day]"))
    const next = buttons[current + offsets[event.key]]
    if (!next) return

    event.preventDefault()
    next.focus()
  }

  initialMonth() {
    const iso = this.fromDateValue || this.toDateValue
    if (!iso) return new Date()

    const date = new Date(`${iso}T00:00:00`)
    return Number.isNaN(date.getTime()) ? new Date() : date
  }

  syncFields() {
    this.fromDateTarget.value = this.fromDateValue || ""
    this.toDateTarget.value = this.toDateValue || ""
  }

  render() {
    this.syncFields()
    this.updateLabels()
    this.renderGrid()
  }

  updateLabels() {
    this.monthLabelTarget.textContent = this.monthTitle()
    this.triggerLabelTarget.textContent = this.rangeLabel()
    this.hintTarget.textContent = this.hintText()
  }

  renderGrid() {
    const year = this.visible.getFullYear()
    const month = this.visible.getMonth()
    const days = new Date(year, month + 1, 0).getDate()
    const offset = new Date(year, month, 1).getDay()
    const cells = WEEKDAYS.map((day) => `<span class="datepicker__dow">${day}</span>`)

    for (let slot = 0; slot < offset; slot += 1) {
      cells.push('<span class="datepicker__cell is-empty" aria-hidden="true"></span>')
    }
    for (let day = 1; day <= days; day += 1) {
      const iso = this.isoDate(this.visible, day)
      const today = iso === this.todayIso()
      const classes = `datepicker__cell${today ? " is-today" : ""}`
      const current = today ? ' aria-current="date"' : ""
      cells.push(`<button type="button" class="${classes}" data-day="${day}"
        aria-label="${this.dayLabel(day)}" aria-pressed="false"${current}>${day}</button>`)
    }

    this.gridTarget.innerHTML = cells.join("")
    this.applyRangeClasses()
  }

  applyRangeClasses() {
    const fromDate = this.fromDateValue
    const toDate = this.toDateValue
    this.gridTarget.querySelectorAll("button[data-day]").forEach((button) => {
      const iso = this.isoDate(this.visible, Number(button.dataset.day))
      button.classList.toggle("is-start", iso === fromDate)
      button.classList.toggle("is-end", iso === toDate)
      button.classList.toggle("is-in-range", Boolean(fromDate && toDate && iso > fromDate && iso < toDate))
      button.setAttribute("aria-pressed", String(Boolean(
        fromDate && toDate && iso >= fromDate && iso <= toDate
      )))
    })
  }

  rangeLabel() {
    if (!this.fromDateValue) return "Escolher intervalo"

    const fromLabel = this.formatDate(this.fromDateValue)
    const toLabel = this.formatDate(this.toDateValue || this.fromDateValue)
    if (fromLabel === toLabel) return fromLabel

    return `${fromLabel} a ${toLabel}`
  }

  hintText() {
    if (this.picking) return "Agora selecione o último dia do intervalo"
    if (this.fromDateValue) return "Intervalo selecionado. Depois, aplique o filtro."

    return "Selecione o primeiro dia do intervalo"
  }

  monthTitle() {
    return `${MONTHS[this.visible.getMonth()]} de ${this.visible.getFullYear()}`
  }

  isoDate(date, day) {
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const dayPart = String(day).padStart(2, "0")
    return `${date.getFullYear()}-${month}-${dayPart}`
  }

  todayIso() {
    const today = new Date()
    return this.isoDate(today, today.getDate())
  }

  dayLabel(day) {
    return `${day} de ${MONTHS[this.visible.getMonth()]} de ${this.visible.getFullYear()}`
  }

  formatDate(iso) {
    const [year, month, day] = iso.split("-")
    return `${day}/${month}/${year}`
  }
}
