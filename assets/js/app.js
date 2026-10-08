import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import { PasskeyLogin, PasskeyRegister } from "./hooks/passkey.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { PasskeyLogin, PasskeyRegister },
})

liveSocket.connect()
window.liveSocket = liveSocket
