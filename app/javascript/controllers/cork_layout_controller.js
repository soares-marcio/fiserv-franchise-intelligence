import { Controller } from "@hotwired/stimulus"

// Casca do layout: menu lateral no mobile, busca global e atalhos de teclado.
export default class extends Controller {
  static targets = ["searchModal", "searchInput", "searchResults", "searchTrigger", "shortcut"]
  static values = { searchUrl: String }

  connect() {
    this.boundKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    // O atalho aceita Cmd no Mac; o rótulo precisa dizer a tecla que o usuário tem.
    if (navigator.platform.startsWith("Mac")) {
      this.shortcutTargets.forEach((element) => { element.textContent = "⌘ /" })
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    clearTimeout(this.searchTimer)
  }

  toggleMobileMenu() {
    this.element.classList.toggle("mobile-menu-open")
  }

  openSearch(event) {
    event?.preventDefault()
    this.returnFocusTo = document.activeElement
    this.searchModalTarget.hidden = false
    this.searchInputTarget.focus()
    this.searchInputTarget.select()
  }

  closeSearch() {
    if (this.searchModalTarget.hidden) return

    this.searchModalTarget.hidden = true
    // Devolve o foco a quem abriu; aberto pelo atalho não há ninguém, então vai ao botão da busca.
    const opener = this.returnFocusTo
    const target = opener && opener !== document.body && opener.isConnected ? opener : this.searchTriggerTarget
    target?.focus()
    this.returnFocusTo = null
  }

  closePanels() {
    this.closeSearch()
    this.element.classList.remove("mobile-menu-open")
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
      this.closePanels()
      return
    }

    if (event.key === "Tab" && !this.searchModalTarget.hidden) this.trapFocus(event)
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
}
