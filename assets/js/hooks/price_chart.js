import { chartHook, cssColor, day, formatDay, reducedMotion, timeAxis, transparent } from "../charts.js"

const TRADES = { buy: "Kauf", inbound_delivery: "Einlieferung", sell: "Verkauf", outbound_delivery: "Auslieferung" }
const PURCHASES = ["buy", "inbound_delivery"]

const priceFormat = new Intl.NumberFormat("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 4 })
const axisFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 2 })
const sharesFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 8 })

// Prices and shares come × 10⁸.
const unscaled = (value) => value / 100_000_000

// A security's prices over the period, its purchases as rings and its sales as dots at their price
// per share; the security page pushes them with the currency they are in. Nothing without prices.
export const PriceChart = chartHook("price-chart", ({ currency, dates, prices, trades }, el) => {
  if (dates.length === 0) return null

  const color = (name) => cssColor(el, name)
  const [primary, success, danger, muted, grid, background] = [
    "--felt-primary",
    "--felt-success-text",
    "--felt-danger-text",
    "--felt-secondary-color",
    "--felt-border-color",
    "--felt-card-bg",
  ].map(color)
  const days = dates.map(day)
  const last = days.length - 1
  // A trade may lie before the first price, or after the last one.
  const span = [...days, ...trades.map((trade) => day(trade.date))]
  const font = { family: getComputedStyle(el).fontFamily, size: 12 }
  const narrow = el.clientWidth < 576
  const price = (value) => `${priceFormat.format(value)}\u00a0${currency}`
  const dots = (purchases) =>
    trades
      .filter((trade) => PURCHASES.includes(trade.type) === purchases)
      .map((trade) => ({ x: day(trade.date), y: unscaled(trade.price), trade }))
  const tradeDots = {
    showLine: false,
    clip: false,
    pointRadius: narrow ? 4 : 4.5,
    pointHoverRadius: narrow ? 5 : 6,
  }

  return {
    type: "line",
    data: {
      datasets: [
        {
          label: "Kurs",
          data: prices.map((value, i) => ({ x: days[i], y: unscaled(value) })),
          borderColor: primary,
          borderWidth: narrow ? 1.75 : 2.5,
          backgroundColor: transparent(primary, 0.14),
          fill: "start",
          clip: false,
          pointRadius: (context) => (context.dataIndex === last ? 4 : 0),
          pointHoverRadius: 4,
          pointBackgroundColor: primary,
          pointBorderColor: background,
          pointBorderWidth: 2,
        },
        {
          ...tradeDots,
          label: "Käufe",
          data: dots(true),
          pointBackgroundColor: background,
          pointBorderColor: success,
          pointBorderWidth: 2.5,
        },
        {
          ...tradeDots,
          label: "Verkäufe",
          data: dots(false),
          pointBackgroundColor: danger,
          pointBorderColor: background,
          pointBorderWidth: 1.5,
        },
      ],
    },
    options: {
      maintainAspectRatio: false,
      animation: reducedMotion() ? false : { duration: 300 },
      interaction: { mode: "nearest", axis: "x", intersect: false },
      layout: { padding: { top: 6, right: 6 } },
      scales: {
        x: {
          ...timeAxis(Math.min(...span), Math.max(...span), { color: muted, font }),
          grid: { display: false },
          border: { display: false },
        },
        y: {
          grid: { color: grid },
          border: { display: false, dash: [3, 4] },
          ticks: { maxTicksLimit: 6, color: muted, font, callback: (value) => `${axisFormat.format(value)}\u00a0${currency}` },
        },
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            title: ([item]) => formatDay(item.parsed.x),
            label: ({ raw: { trade }, parsed }) =>
              trade
                ? ` ${TRADES[trade.type]}: ${sharesFormat.format(unscaled(trade.shares))} Stück à ${price(parsed.y)}`
                : ` Kurs: ${price(parsed.y)}`,
          },
        },
      },
    },
  }
})
