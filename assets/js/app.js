import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import { NetWorthChart } from "./hooks/net_worth_chart.js"
import { PasskeyLogin, PasskeyRegister } from "./hooks/passkey.js"
import { Sidebar } from "./hooks/sidebar.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { NetWorthChart, PasskeyLogin, PasskeyRegister, Sidebar },
})

liveSocket.connect()
window.liveSocket = liveSocket
