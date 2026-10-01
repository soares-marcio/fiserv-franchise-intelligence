import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Depois da troca, a barra fica no começo da área útil, logo abaixo do cabeçalho fixo.
// Antes de navegar, ela chega até lá numa transição curta; a página nova entra já alinhada.
// Isso evita animar do topo depois da resposta, que pareceria o mesmo pisca de antes.
const TRANSITION_DURATION = 420
let pending = false
let generation = 0

function topbarBottom() {
  return document.querySelector(".topbar")?.getBoundingClientRect().bottom || 0
}

function restore() {
  if (!pending) return

  const tabs = document.querySelector("nav.variation-tabs")
  if (!tabs) return

  const delta = tabs.getBoundingClientRect().top - topbarBottom()
  if (Math.abs(delta) < 1) return

  window.scrollBy({ top: delta, left: 0, behavior: "instant" })
}

function release(current) {
  if (current !== generation) return

  window.removeEventListener("scroll", restore)
  pending = false
}

function moveToFold(element, current, complete) {
  const startY = window.scrollY
  const delta = element.getBoundingClientRect().top - topbarBottom()
  const maxY = Math.max(document.documentElement.scrollHeight - window.innerHeight, 0)
  const targetY = Math.min(Math.max(startY + delta, 0), maxY)
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches

  if (reducedMotion || Math.abs(targetY - startY) < 1) {
    window.scrollTo({ top: targetY, left: window.scrollX, behavior: "instant" })
    complete()
    return
  }

  const startedAt = performance.now()
  const step = (now) => {
    if (current !== generation) return

    const progress = Math.min((now - startedAt) / TRANSITION_DURATION, 1)
    const eased = progress * progress * (3 - (2 * progress))
    const top = startY + ((targetY - startY) * eased)
    window.scrollTo({ top, left: window.scrollX, behavior: "instant" })

    if (progress < 1) {
      requestAnimationFrame(step)
    } else {
      complete()
    }
  }

  requestAnimationFrame(step)
}

document.addEventListener("turbo:click", (event) => {
  const link = event.target.closest?.("a")
  if (link?.closest("nav.variation-tabs")) return

  generation += 1
  window.removeEventListener("scroll", restore)
  pending = false
})

export default class extends Controller {
  navigate(event) {
    if (event.defaultPrevented || event.button !== 0) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const link = event.target.closest("a")
    if (!link || link.target === "_blank") return

    const current = ++generation
    event.preventDefault()

    if (link.matches("[aria-current='page']")) {
      moveToFold(this.element, current, () => {})
      return
    }

    let transitionFinished = false
    let resumeRender = null

    document.addEventListener("turbo:before-render", (renderEvent) => {
      if (current !== generation || transitionFinished) return

      renderEvent.preventDefault()
      resumeRender = renderEvent.detail.resume
    }, { once: true })

    document.addEventListener("turbo:load", () => {
      if (current !== generation) return

      restore()
      requestAnimationFrame(() => {
        restore()
        release(current)
      })
    }, { once: true })

    moveToFold(this.element, current, () => {
      if (current !== generation) return

      transitionFinished = true
      pending = true
      window.addEventListener("scroll", restore)
      resumeRender?.()
    })

    Turbo.visit(link.href)
  }
}
