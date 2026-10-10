import { chartHook, cssColor, formatAxisEuros, formatEuros, reducedMotion } from "../charts.js"

const MONTHS = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
const numberFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 1 })

function niceAxis(peak) {
  if (peak <= 0) return { step: 1, max: 5 }
  const rough = peak / 5
  const power = 10 ** Math.floor(Math.log10(rough))
  const step = [1, 2, 2.5, 5, 10].map((n) => n * power).find((n) => n >= rough)
  return { step, max: Math.ceil(peak / step) * step }
}

const unitlessAxis = (euros) => (euros >= 1000 ? `${numberFormat.format(euros / 1000)} T` : numberFormat.format(euros))

export const DividendChart = chartHook("dividend-chart", ({ years }, el) => {
  const color = (name) => cssColor(el, name)
  const [muted, grid, axis] = ["--felt-secondary-color", "--felt-border-color", "--felt-tertiary-color"].map(color)
  const font = { family: getComputedStyle(el).fontFamily, size: 12 }
  const narrow = el.clientWidth < 576
  const euros = years.map(({ amounts }) => amounts.map((cents) => cents / 100))
  const { step, max } = niceAxis(Math.max(0, ...euros.flat()))

  return {
    type: "bar",
    data: {
      labels: narrow ? MONTHS.map((month) => month[0]) : MONTHS,
      datasets: years.map(({ year, colour }, i) => ({
        label: String(year),
        data: euros[i],
        backgroundColor: color(colour),
        borderRadius: { topLeft: 3, topRight: 3 },
        borderSkipped: "start",
        categoryPercentage: narrow ? 0.94 : 0.86,
        barPercentage: narrow ? 1 : 0.9,
      })),
    },
    options: {
      maintainAspectRatio: false,
      animation: reducedMotion() ? false : { duration: 300 },
      interaction: { mode: "index", intersect: false },
      layout: { padding: { top: 6, bottom: 0 } },
      scales: {
        x: {
          grid: { display: false },
          border: { display: true, color: axis },
          ticks: { color: muted, font, maxRotation: 0, autoSkip: false },
        },
        y: {
          min: 0,
          max,
          grid: { color: grid, drawTicks: false },
          border: { display: false, dash: [3, 4] },
          ticks: { stepSize: step, padding: 6, color: muted, font, callback: narrow ? unitlessAxis : formatAxisEuros },
        },
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            title: ([item]) => MONTHS[item.dataIndex],
            label: (item) => ` ${item.dataset.label}: ${formatEuros(item.parsed.y)}`,
          },
        },
      },
    },
  }
})
