import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchModal"]

  connect() {
    this.boundKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  toggleMobileMenu() {
    this.element.classList.toggle("mobile-menu-open")
  }

  openSearch(event) {
    event?.preventDefault()
    this.searchModalTarget.hidden = false
    this.searchModalTarget.querySelector("a, button")?.focus()
  }

  closeSearch() {
    this.searchModalTarget.hidden = true
  }

  closePanels() {
    this.closeSearch()
    this.element.classList.remove("mobile-menu-open")
  }

  keydown(event) {
    if ((event.ctrlKey || event.metaKey) && event.key === "/") {
      event.preventDefault()
      this.openSearch()
      return
    }

    if (event.key === "Escape") {
      this.closePanels()
    }
  }
}
