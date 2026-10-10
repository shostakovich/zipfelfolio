import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

import { DividendChart, UpcomingDividendChart } from "./hooks/dividend_chart.js"
import { NetWorthChart } from "./hooks/net_worth_chart.js"
import { PasskeyLogin, PasskeyRegister } from "./hooks/passkey.js"
import { PriceChart } from "./hooks/price_chart.js"
import { Sidebar } from "./hooks/sidebar.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { DividendChart, NetWorthChart, PasskeyLogin, PasskeyRegister, PriceChart, Sidebar, UpcomingDividendChart },
})

liveSocket.connect()
window.liveSocket = liveSocket
