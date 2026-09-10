import { Controller } from "@hotwired/stimulus"

// A barra de contexto e o cabeçalho das colunas ficam empilhados ao rolar. As alturas variam
// por página, então são medidas para que uma camada não encubra a outra.
export default class extends Controller {
  connect() {
    this.toolbar = this.element.querySelector(".table-toolbar")
    if (!this.toolbar) return

    this.tabs = this.element.previousElementSibling?.matches(".variation-tabs-wrap")
      ? this.element.previousElementSibling
      : null
    this.tableScroll = this.element.querySelector(".table-scroll")
    this.table = this.tableScroll?.querySelector("table")
    this.thead = this.table?.tHead
    this.update = this.update.bind(this)
    this.syncMobileHeader = this.syncMobileHeader.bind(this)

    this.createMobileHeader()
    this.update()
    this.observer = new ResizeObserver(this.update)
    this.observer.observe(this.toolbar)
    if (this.tabs) this.observer.observe(this.tabs)
    if (this.table) this.observer.observe(this.table)
    this.tableScroll?.addEventListener("scroll", this.syncMobileHeader, { passive: true })
    window.addEventListener("scroll", this.syncMobileHeader, { passive: true })
    window.addEventListener("resize", this.update)
  }

  disconnect() {
    this.observer?.disconnect()
    this.tableScroll?.removeEventListener("scroll", this.syncMobileHeader)
    window.removeEventListener("scroll", this.syncMobileHeader)
    window.removeEventListener("resize", this.update)
    this.mobileHeader?.remove()
  }

  update() {
    this.element.style.setProperty("--toolbar-height", `${this.toolbar.offsetHeight}px`)
    this.element.style.setProperty("--variation-tabs-height", `${this.tabs?.offsetHeight || 0}px`)
    this.syncColumnWidths()
    this.syncMobileHeader()
  }

  createMobileHeader() {
    if (!this.table || !this.thead) return

    this.mobileHeader = document.createElement("div")
    this.mobileHeader.className = "mobile-table-head"
    this.mobileHeader.setAttribute("aria-hidden", "true")
    this.mobileTable = this.table.cloneNode(false)
    this.mobileTable.classList.add("mobile-table-head__table")
    this.mobileTable.append(this.thead.cloneNode(true))
    this.mobileTable.querySelectorAll("a, button, input, select, textarea").forEach((element) => {
      element.tabIndex = -1
    })
    this.mobileHeader.append(this.mobileTable)
    document.body.append(this.mobileHeader)
  }

  syncMobileHeader() {
    if (!this.mobileHeader || !this.tableScroll || !this.thead) return

    const isMobile = window.matchMedia("(max-width: 1023px)").matches
    if (!isMobile) {
      this.mobileHeader.classList.remove("is-visible")
      return
    }

    const scrollBounds = this.tableScroll.getBoundingClientRect()
    const headerBounds = this.thead.getBoundingClientRect()
    const topbarHeight = Number.parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue("--topbar-height")
    ) || 76
    const stickyTop = topbarHeight + (this.tabs?.offsetHeight || 0) + this.toolbar.offsetHeight
    const isWithinTable = headerBounds.top <= stickyTop && scrollBounds.bottom > stickyTop + headerBounds.height

    this.mobileHeader.style.setProperty("--mobile-head-left", `${scrollBounds.left}px`)
    this.mobileHeader.style.setProperty("--mobile-head-top", `${stickyTop}px`)
    this.mobileHeader.style.setProperty("--mobile-head-width", `${scrollBounds.width}px`)
    this.mobileHeader.style.setProperty("--mobile-table-width", `${this.table.scrollWidth}px`)
    this.mobileTable.style.transform = `translateX(${-this.tableScroll.scrollLeft}px)`
    this.mobileHeader.classList.toggle("is-visible", isWithinTable)
  }

  syncColumnWidths() {
    if (!this.mobileTable) return

    const sourceHeaders = this.thead.querySelectorAll("th")
    const clonedHeaders = this.mobileTable.querySelectorAll("th")
    sourceHeaders.forEach((header, index) => {
      clonedHeaders[index].style.width = `${header.getBoundingClientRect().width}px`
    })
  }
}
