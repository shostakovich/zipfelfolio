// The sidebar from 768 px: from 1280 px open or collapsed to a rail as stored on this device, below
// it a rail that opens over the page. The root layout applies the stored choice before the first
// paint; the classes live on the root element, which LiveView never patches. Attributes inside the
// LiveView are set with this.js(), so that patches keep them.
const KEY = "sidebar"
const wide = matchMedia("(min-width: 1280px)")
const sidebarShown = matchMedia("(min-width: 768px)")
const root = document.documentElement

// The choice made on this page, for a browser that keeps none, e.g. with storage blocked.
let choice = null

const stored = () => {
  if (choice) return choice
  try { return localStorage.getItem(KEY) } catch { return null }
}

const store = (value) => {
  choice = value
  try { localStorage.setItem(KEY, value) } catch {}
}

export const Sidebar = {
  mounted() {
    this.peek = false
    this.toggle = this.el.querySelector("#side-toggle")
    this.onClick = (e) => this.click(e)
    this.onKeydown = (e) => this.keydown(e)
    this.onResize = () => this.layout()
    this.onHide = () => sidebarShown.matches || this.close(false)
    document.addEventListener("click", this.onClick)
    document.addEventListener("keydown", this.onKeydown)
    wide.addEventListener("change", this.onResize)
    sidebarShown.addEventListener("change", this.onHide)
    this.layout()
  },

  destroyed() {
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("keydown", this.onKeydown)
    wide.removeEventListener("change", this.onResize)
    sidebarShown.removeEventListener("change", this.onHide)
    root.classList.remove("app-side-peek")
    root.classList.toggle("app-rail", !wide.matches || stored() === "rail")
  },

  layout() {
    if (wide.matches) this.peek = false
    const rail = wide.matches ? stored() === "rail" : !this.peek
    root.classList.toggle("app-rail", rail)
    root.classList.toggle("app-side-peek", this.peek)

    // While it lies over the page, the rest of the page is out of reach.
    const js = this.js()
    for (const el of document.querySelectorAll("#main, #phone-header, #tabbar")) {
      if (this.peek) js.setAttribute(el, "inert", "")
      else js.removeAttribute(el, "inert")
    }
    js.setAttribute(this.toggle, "aria-label", rail ? "Seitenleiste ausklappen" : "Seitenleiste einklappen")
    js.setAttribute(this.toggle, "aria-expanded", String(!rail))
  },

  open() {
    this.peek = true
    this.layout()
    const target = this.el.querySelector(".nav-link.active") || this.el.querySelector(".nav-link")
    target.focus()
  },

  // Back to the toggle, unless a link in the sidebar was followed.
  close(refocus = true) {
    if (!this.peek) return
    this.peek = false
    this.layout()
    if (refocus) this.toggle.focus()
  },

  click(e) {
    if (e.target.closest("#side-toggle")) {
      if (wide.matches) {
        store(root.classList.contains("app-rail") ? "open" : "rail")
        this.layout()
      } else if (this.peek) {
        this.close()
      } else {
        this.open()
      }
    } else if (e.target.closest("#side-scrim")) {
      this.close()
    } else if (e.target.closest("#sidebar a[href]")) {
      this.close(false)
    }
  },

  keydown(e) {
    if (!this.peek) return
    if (e.key === "Escape" && !this.el.querySelector(".dropdown-menu.show")) this.close()
    if (e.key !== "Tab") return

    // Tab and Shift+Tab go round inside the sidebar.
    const stops = [...this.el.querySelectorAll("a[href], button:not([disabled])")]
      .filter((el) => el.getClientRects().length)
    const first = stops[0]
    const last = stops[stops.length - 1]
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault()
      first.focus()
    }
  },
}
