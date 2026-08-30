import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dialog", "title", "identity", "previousTotal", "comparableTotal",
    "currentTotal", "comparableHint", "currentHint", "daysBody", "cutoffHint",
    "iconUp", "iconDown", "iconFlat"
  ]

  open(event) {
    const source = event.currentTarget.dataset
    const previousDays = this.parseDays(source.diasM1)
    const currentDays = this.parseDays(source.diasAtual)
    const fromDay = Number(source.fromDay || 1)
    const toDay = Number(source.toDay || source.cutoff || 0)
    const name = source.nome || source.razao || "Estabelecimento"

    this.titleTarget.textContent = `EC ${source.ec}`
    this.identityTarget.textContent = [source.cnpj, name].filter(Boolean).join(" · ")
    this.previousTotalTarget.textContent = this.formatBrl(source.faturamentoM1Cheio)
    this.comparableTotalTarget.textContent = this.formatBrl(source.faturamentoM1)
    this.currentTotalTarget.textContent = this.formatBrl(source.faturamentoAtual)
    this.comparableHintTarget.textContent = toDay
      ? `Mês anterior até dia ${toDay}`
      : ""
    this.currentHintTarget.textContent = toDay
      ? `Movimento até dia ${toDay}`
      : ""
    this.cutoffHintTarget.textContent = toDay
      ? `Cada dia compara o mesmo dia nos dois meses. Base comparável do dia ${fromDay} ao dia ${toDay}.`
      : ""
    this.daysBodyTarget.innerHTML = this.rowsHtml(
      this.mergeDays(previousDays, currentDays),
      Number(source.faturamentoM1),
      Number(source.faturamentoAtual),
      fromDay,
      toDay
    )
    this.dialogTarget.showModal()
  }

  parseDays(payload) {
    if (!payload) return []

    try {
      return Object.entries(JSON.parse(payload)).sort(
        ([left], [right]) => Number(left) - Number(right)
      )
    } catch {
      return []
    }
  }

  mergeDays(previousDays, currentDays) {
    const rows = new Map()

    previousDays.forEach(([day, amount]) => {
      rows.set(Number(day), {
        day: Number(day),
        previous: Number(amount),
        hasPrevious: true,
        current: 0,
        hasCurrent: false
      })
    })

    currentDays.forEach(([day, amount]) => {
      const key = Number(day)
      const row = rows.get(key) || {
        day: key, previous: 0, hasPrevious: false, current: 0, hasCurrent: false
      }
      row.current = Number(amount)
      row.hasCurrent = true
      rows.set(key, row)
    })

    return [...rows.values()].sort((left, right) => left.day - right.day)
  }

  rowsHtml(days, comparableTotal, currentTotal, fromDay, toDay) {
    if (days.length === 0) {
      return '<tr><td colspan="4" class="opacity-60">Sem lançamento neste recorte.</td></tr>'
    }

    const rows = days.map((row) => this.dayRow(row, fromDay, toDay))
    const label = toDay ? `Total dos dias ${fromDay} a ${toDay}` : "Total"
    rows.push(`<tr class="font-bold">
      <td>${label}</td>
      <td class="text-right tabular-nums">${this.formatBrl(comparableTotal)}</td>
      <td class="text-right tabular-nums">${this.formatBrl(currentTotal)}</td>
      <td class="text-right">${this.variationChip(comparableTotal, currentTotal)}</td>
    </tr>`)

    return rows.join("")
  }

  dayRow(row, fromDay, toDay) {
    const beyond = (fromDay > 0 && row.day < fromDay) || (toDay > 0 && row.day > toDay)
    const hint = beyond
      ? '<span class="block text-xs opacity-60">fora da base comparável</span>'
      : ""
    const previous = !beyond && row.hasPrevious ? row.previous : 0
    const current = !beyond && row.hasCurrent ? row.current : 0

    return `<tr>
      <td>Dia ${row.day}${hint}</td>
      <td class="text-right tabular-nums">${this.amountCell(row.previous, row.hasPrevious)}</td>
      <td class="text-right tabular-nums">${this.amountCell(row.current, row.hasCurrent && !beyond)}</td>
      <td class="text-right">${this.variationChip(previous, current)}</td>
    </tr>`
  }

  amountCell(amount, present) {
    if (!present) return '<span class="opacity-60">—</span>'

    return this.formatBrl(amount)
  }

  variationChip(previous, current) {
    const prev = Number(previous)
    const curr = Number(current)
    if (!prev) return '<span class="variation-chip variation-chip--empty">—</span>'

    const label = new Intl.NumberFormat("pt-BR", {
      style: "percent",
      signDisplay: "exceptZero",
      minimumFractionDigits: 1,
      maximumFractionDigits: 1
    }).format(curr / prev - 1)

    let direction = "flat"
    let verb = "Estável"
    if (curr > prev) {
      direction = "up"
      verb = "Subiu"
    } else if (curr < prev) {
      direction = "down"
      verb = "Caiu"
    }

    return `<span class="variation-chip variation-chip--${direction}" aria-label="${verb} ${label}">
      ${this.variationIcon(direction, verb)}
      <span class="variation-chip__value">${label}</span>
    </span>`
  }

  variationIcon(direction, verb) {
    const template = {
      up: this.iconUpTarget,
      down: this.iconDownTarget,
      flat: this.iconFlatTarget
    }[direction]

    return `<span class="tooltip tooltip-left variation-icon-tip" data-tip="${verb}"
      tabindex="0">${template.innerHTML}</span>`
  }

  formatBrl(amount) {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(
      Number(amount || 0)
    )
  }
}
