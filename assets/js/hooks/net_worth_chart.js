import { chartHook, cssColor, day, formatAxisEuros, formatDay, formatEuros, reducedMotion, timeAxis, transparent } from "../charts.js"

// Net worth against invested capital; the overview pushes the days of its period with the amounts
// in cents.
export const NetWorthChart = chartHook("net-worth-chart", ({ dates, net_worth, invested_capital }, el) => {
  const color = (name) => cssColor(el, name)
  const [primary, secondary, muted, grid, background] =
    ["--felt-primary", "--felt-secondary", "--felt-secondary-color", "--felt-border-color", "--felt-card-bg"].map(color)
  const days = dates.map(day)
  const points = (cents) => cents.map((amount, i) => ({ x: days[i], y: amount / 100 }))
  const last = days.length - 1
  const font = { family: getComputedStyle(el).fontFamily, size: 12 }
  const narrow = el.clientWidth < 576

  return {
    type: "line",
    data: {
      datasets: [
        {
          label: "Vermögen",
          data: points(net_worth),
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
          label: "Investiert",
          data: points(invested_capital),
          borderColor: secondary,
          borderWidth: narrow ? 1.5 : 1.75,
          borderDash: [5, 4],
          stepped: true,
          pointRadius: 0,
          pointHoverRadius: 4,
          pointBackgroundColor: secondary,
        },
      ],
    },
    options: {
      maintainAspectRatio: false,
      animation: reducedMotion() ? false : { duration: 300 },
      interaction: { mode: "index", intersect: false },
      layout: { padding: { top: 6, right: 6 } },
      scales: {
        x: {
          ...timeAxis(days[0], days[last], { color: muted, font }),
          grid: { display: false },
          border: { display: false },
        },
        y: {
          grid: { color: grid },
          border: { display: false, dash: [3, 4] },
          ticks: { maxTicksLimit: 6, color: muted, font, callback: formatAxisEuros },
        },
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            title: ([item]) => formatDay(item.parsed.x),
            label: (item) => ` ${item.dataset.label}: ${formatEuros(item.parsed.y)}`,
          },
        },
      },
    },
  }
})
