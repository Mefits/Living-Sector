// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Hooks
const Hooks = {
  PanZoomMap: {
    mounted() {
      const el = this.el
      const svg = el.querySelector("svg")
      if (!svg) return

      // View state — start zoomed out to show universe
      this.vx = -15
      this.vy = -15
      this.vw = 50
      this.vh = 35
      this.isPanning = false
      this.startX = 0
      this.startY = 0
      this.startVx = 0
      this.startVy = 0
      this.hasMoved = false

      this._applyViewBox = () => {
        svg.setAttribute("viewBox", `${this.vx} ${this.vy} ${this.vw} ${this.vh}`)
      }

      this._svgPoint = (clientX, clientY) => {
        const pt = svg.createSVGPoint()
        pt.x = clientX
        pt.y = clientY
        return pt.matrixTransform(svg.getScreenCTM().inverse())
      }

      // Zoom with scroll wheel
      el.addEventListener("wheel", (e) => {
        e.preventDefault()
        const factor = e.deltaY > 0 ? 1.06 : 0.94
        const p = this._svgPoint(e.clientX, e.clientY)

        // Zoom around cursor position
        const newW = this.vw * factor
        const newH = this.vh * factor
        this.vx = p.x - (p.x - this.vx) * (newW / this.vw)
        this.vy = p.y - (p.y - this.vy) * (newH / this.vh)
        this.vw = newW
        this.vh = newH
        this._applyViewBox()
      }, {passive: false})

      // Pan with drag
      el.addEventListener("mousedown", (e) => {
        if (e.button !== 0) return
        this.isPanning = true
        this.hasMoved = false
        this.startX = e.clientX
        this.startY = e.clientY
        this.startVx = this.vx
        this.startVy = this.vy
        el.style.cursor = "grabbing"
      })

      window.addEventListener("mousemove", this._onMouseMove = (e) => {
        if (!this.isPanning) return
        const dx = e.clientX - this.startX
        const dy = e.clientY - this.startY
        if (Math.abs(dx) > 3 || Math.abs(dy) > 3) this.hasMoved = true

        // Convert pixel delta to SVG units
        const rect = svg.getBoundingClientRect()
        const scaleX = this.vw / rect.width
        const scaleY = this.vh / rect.height
        this.vx = this.startVx - dx * scaleX
        this.vy = this.startVy - dy * scaleY
        this._applyViewBox()
      })

      window.addEventListener("mouseup", this._onMouseUp = (e) => {
        if (!this.isPanning) return
        this.isPanning = false
        el.style.cursor = ""

        // If we didn't pan, treat as click
        if (!this.hasMoved) {
          const p = this._svgPoint(e.clientX, e.clientY)

          // Check if clicking a system node (for zoom_system)
          const target = e.target.closest("[data-system-id]")
          if (target) {
            this.pushEvent("zoom_system", {system: target.dataset.systemId})
            return
          }

          // Otherwise move observer if chunks active
          if (el.dataset.chunksActive === "true") {
            this.pushEvent("move_observer", {x: p.x, y: p.y})
          }
        }
      })

      this._applyViewBox()
    },

    updated() {
      // LiveView patched the DOM — re-apply our viewBox so it doesn't reset
      const svg = this.el.querySelector("svg")
      if (svg) svg.setAttribute("viewBox", `${this.vx} ${this.vy} ${this.vw} ${this.vh}`)
    },

    destroyed() {
      if (this._onMouseMove) window.removeEventListener("mousemove", this._onMouseMove)
      if (this._onMouseUp) window.removeEventListener("mouseup", this._onMouseUp)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Server log streaming disabled — too noisy with 250+ agents ticking.
    // Enable manually in console: window.liveReloader.enableServerLogs()
    reloader.disableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

