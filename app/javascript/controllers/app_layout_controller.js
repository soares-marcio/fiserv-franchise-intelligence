import { Controller } from "@hotwired/stimulus"

// Casca do layout: busca global e atalhos de teclado.
export default class extends Controller {
  static targets = ["searchModal", "searchInput", "searchResults", "searchTrigger", "shortcut",
    "primaryNav", "navToggle", "navBackdrop"]
  static values = { searchUrl: String }

  connect() {
    this.boundKeydown = this.keydown.bind(this)
    this.boundBeforeVisit = this.closeNav.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    document.addEventListener("turbo:before-visit", this.boundBeforeVisit)
    // O mesmo limite do CSS em que o menu deixa de ser recolhido.
    this.desktopMedia = window.matchMedia("(min-width: 1200px)")
    this.boundViewportChange = (event) => {
      if (event.matches) this.closeNav()
    }
    this.desktopMedia.addEventListener("change", this.boundViewportChange)
    this.trackTopbarHeight()
    // O atalho aceita Cmd no Mac; o rótulo precisa dizer a tecla que o usuário tem.
    if (navigator.platform.startsWith("Mac")) {
      this.shortcutTargets.forEach((element) => { element.textContent = "⌘ /" })
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    document.removeEventListener("turbo:before-visit", this.boundBeforeVisit)
    this.desktopMedia?.removeEventListener("change", this.boundViewportChange)
    clearTimeout(this.searchTimer)
    this.topbarObserver?.disconnect()
    document.body.classList.remove("has-mobile-overlay")
    this.mainContent()?.removeAttribute("inert")
  }

  toggleNav() {
    this.navOpen() ? this.closeNav(true) : this.openNav()
  }

  openNav() {
    this.closeSearch()
    this.primaryNavTarget.classList.add("is-open")
    this.navToggleTarget.setAttribute("aria-expanded", "true")
    this.navBackdropTarget.hidden = false
    document.body.classList.add("has-mobile-overlay")
    this.mainContent()?.setAttribute("inert", "")
    this.navFocusable()[0]?.focus()
  }

  closeNav(restoreFocus = false) {
    if (!this.navOpen()) return

    this.primaryNavTarget.classList.remove("is-open")
    this.navToggleTarget.setAttribute("aria-expanded", "false")
    this.navBackdropTarget.hidden = true
    this.releasePage()
    if (restoreFocus) this.navToggleTarget.focus()
  }

  closeNavOnBackdrop() {
    this.closeNav(true)
  }

  // A barra muda de altura quando o menu quebra linha; os cabeçalhos fixos das tabelas
  // precisam saber onde ela termina para ficarem logo abaixo.
  trackTopbarHeight() {
    const topbar = this.element.querySelector(".topbar")
    if (!topbar) return

    const update = () => document.documentElement.style.setProperty("--topbar-height", `${topbar.offsetHeight}px`)
    update()
    this.topbarObserver = new ResizeObserver(update)
    this.topbarObserver.observe(topbar)
  }

  openSearch(event) {
    event?.preventDefault()
    this.closeNav()
    this.returnFocusTo = document.activeElement
    this.searchModalTarget.hidden = false
    document.body.classList.add("has-mobile-overlay")
    this.mainContent()?.setAttribute("inert", "")
    this.searchInputTarget.focus()
    this.searchInputTarget.select()
  }

  closeSearch(restoreFocus = true) {
    if (this.searchModalTarget.hidden) return

    this.searchModalTarget.hidden = true
    this.releasePage()
    // Devolve o foco a quem abriu; aberto pelo atalho não há ninguém, então vai ao botão da busca.
    const opener = this.returnFocusTo
    const target = opener && opener !== document.body && opener.isConnected ? opener : this.searchTriggerTarget
    if (restoreFocus) target?.focus()
    this.returnFocusTo = null
  }

  closeSearchOnBackdrop(event) {
    if (event.target === this.searchModalTarget) this.closeSearch()
  }

  // Espera o usuário parar de digitar antes de consultar o servidor.
  search() {
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.loadResults(), 200)
  }

  loadResults() {
    const query = this.searchInputTarget.value.trim()
    if (query === this.lastQuery) return

    this.lastQuery = query
    this.searchResultsTarget.src = `${this.searchUrlValue}?q=${encodeURIComponent(query)}`
  }

  searchKeydown(event) {
    const first = this.searchResultsTarget.querySelector("a[href]")
    if (event.key === "Enter" && first) {
      event.preventDefault()
      first.click()
    } else if (event.key === "ArrowDown" && first) {
      event.preventDefault()
      first.focus()
    }
  }

  keydown(event) {
    if ((event.ctrlKey || event.metaKey) && event.key === "/") {
      event.preventDefault()
      this.openSearch()
      return
    }

    if (event.key === "Escape") {
      if (!this.searchModalTarget.hidden) this.closeSearch()
      else this.closeNav(true)
      return
    }

    if (event.key === "Tab" && !this.searchModalTarget.hidden) this.trapFocus(event)
    else if (event.key === "Tab" && this.navOpen()) this.trapNavFocus(event)
  }

  // aria-modal promete que o Tab não sai do diálogo; o navegador não faz isso sozinho.
  trapFocus(event) {
    const focusable = [...this.searchModalTarget.querySelectorAll("input, button, a[href]")]
      .filter((element) => !element.hidden && element.offsetParent !== null)
    if (focusable.length === 0) return

    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  trapNavFocus(event) {
    const focusable = this.navFocusable()
    if (focusable.length === 0) return

    const first = focusable[0]
    const last = focusable.at(-1)
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  navFocusable() {
    return [...this.primaryNavTarget.querySelectorAll("a[href], button:not([disabled])")]
      .filter((element) => element.offsetParent !== null)
  }

  navOpen() {
    return this.primaryNavTarget.classList.contains("is-open")
  }

  mainContent() {
    return document.getElementById("main-content")
  }

  releasePage() {
    if (this.navOpen() || !this.searchModalTarget.hidden) return

    document.body.classList.remove("has-mobile-overlay")
    this.mainContent()?.removeAttribute("inert")
  }
}
