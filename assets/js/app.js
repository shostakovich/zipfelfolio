import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/zipfelfolio"
import { hooks as setzkastenHooks } from "phoenix-colocated/setzkasten"

import { benchmarkChoice } from "./benchmark.js"
import { DividendChart, UpcomingDividendChart } from "./hooks/dividend_chart.js"
import { NetWorthChart } from "./hooks/net_worth_chart.js"
import { PasskeyLogin, PasskeyRegister } from "./hooks/passkey.js"
import { PriceChart } from "./hooks/price_chart.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const appHooks = { DividendChart, NetWorthChart, PasskeyLogin, PasskeyRegister, PriceChart, UpcomingDividendChart }

const liveSocket = new LiveSocket("/live", Socket, {
  // A function, so that each page that connects, live navigation too, sends the current choice.
  params: () => ({ _csrf_token: csrfToken, benchmark: benchmarkChoice() }),
  hooks: { ...colocatedHooks, ...setzkastenHooks, ...appHooks },
})

liveSocket.connect()
window.liveSocket = liveSocket
