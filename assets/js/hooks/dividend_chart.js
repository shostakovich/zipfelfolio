import { MONTHS, chartHook, cssColor, formatAxisEuros, formatEuros, reducedMotion, transparent } from "../charts.js"

const numberFormat = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 1 })

function niceAxis(peak) {
  if (peak <= 0) return { step: 1, max: 5 }
  const power = 10 ** Math.floor(Math.log10(peak / 5))
  const steps = [0.1, 1, 10].flatMap((p) => [1, 2, 2.5, 5].map((n) => n * p * power))
  const fits = steps
    .map((step) => ({ step, max: Math.ceil(peak / step) * step }))
    .filter(({ step, max }) => max / step >= 3 && max / step <= 5)
  return fits.reduce((best, s) => (s.max < best.max || (s.max === best.max && s.step > best.step) ? s : best))
}

const unitlessAxis = (euros) => (euros >= 1000 ? `${numberFormat.format(euros / 1000)} T` : numberFormat.format(euros))

function barOptions(el, { step, max, narrow, stacked = false, tooltip }) {
  const color = (name) => cssColor(el, name)
  const [muted, grid, axis] = ["--felt-secondary-color", "--felt-border-color", "--felt-tertiary-color"].map(color)
  const font = { family: getComputedStyle(el).fontFamily, size: 12 }

  return {
    maintainAspectRatio: false,
    animation: reducedMotion() ? false : { duration: 300 },
    interaction: { mode: "index", intersect: false },
    layout: { padding: { top: 6, bottom: 0 } },
    scales: {
      x: {
        stacked,
        grid: { display: false },
        border: { display: true, color: axis },
        ticks: { color: muted, font, maxRotation: 0, autoSkip: false },
      },
      y: {
        stacked,
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
        ...tooltip,
        callbacks: {
          label: (item) => ` ${item.dataset.label}: ${formatEuros(item.parsed.y)}`,
          ...tooltip.callbacks,
        },
      },
    },
  }
}

export const DividendChart = chartHook("dividend-chart", ({ years }, el) => {
  const color = (name) => cssColor(el, name)
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
    options: barOptions(el, {
      step,
      max,
      narrow,
      tooltip: { callbacks: { title: ([item]) => MONTHS[item.dataIndex] } },
    }),
  }
})

export const UpcomingDividendChart = chartHook("upcoming-dividend-chart", ({ months }, el) => {
  const now = cssColor(el, "--app-year-now")
  const narrow = el.clientWidth < 360
  const announced = months.map((month) => month.announced / 100)
  const forecast = months.map((month) => month.forecast / 100)
  const { step, max } = niceAxis(Math.max(0, ...announced.map((euros, i) => euros + forecast[i])))
  const bar = { borderSkipped: "start", categoryPercentage: narrow ? 0.8 : 0.7, barPercentage: 1 }
  const top = { topLeft: 3, topRight: 3 }

  return {
    type: "bar",
    data: {
      labels: months.map(({ label, year }) => {
        const text = narrow ? label[0] : label
        return year ? [text, narrow ? `’${String(year).slice(2)}` : String(year)] : text
      }),
      datasets: [
        { ...bar, label: "angekündigt", data: announced, backgroundColor: now,
          borderRadius: ({ dataIndex }) => (forecast[dataIndex] > 0 ? 0 : top) },
        {
          ...bar,
          label: "Prognose",
          data: forecast,
          // Matches --app-forecast in app.css.
          backgroundColor: transparent(now, matchMedia("(prefers-color-scheme: dark)").matches ? 0.55 : 0.3),
          borderColor: now,
          borderWidth: 1,
          borderRadius: top,
        },
      ],
    },
    options: barOptions(el, {
      step,
      max,
      narrow,
      stacked: true,
      tooltip: {
        filter: (item) => item.parsed.y > 0,
        callbacks: { title: ([item]) => months[item.dataIndex].title },
      },
    }),
  }
})
