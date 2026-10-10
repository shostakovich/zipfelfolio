# zipfelfolio

A self-hosted portfolio tracker for one household: holdings, performance, dividends (history, calendar,
forecast) and a savings plan. It is meant to replace [Portfolio Performance](https://www.portfolio-performance.info/)
and a [DivvyDiary](https://divvydiary.com/) subscription. **The user interface is German.**

## Status

Built so far: the import of a Portfolio Performance file, prices from Yahoo and ECB exchange rates fetched daily,
the overview (net worth, its chart, TTWROR, IRR, dividends with the next ones), the performance screen (TTWROR, IRR,
drawdown and volatility, the breakdown of the change in value, monthly returns as a heatmap), a benchmark of the
user's choice (its TTWROR beside the portfolios' and a shadow portfolio in it on the overview's chart), the holdings
with costs, allocation and dividend yield, a page per security with its next payments, and the dividends received
per month and year with a calendar of the coming ones; sign-in with passkeys or a link by email, container and
deploy.

- [Issues](https://github.com/shostakovich/zipfelfolio/issues): scope and decisions per feature, milestones v1–v4
- `mockup/`: click dummy with example data, built with [felt-css](https://felt-css.rocu.de/)

## Development

Elixir and Erlang as in `.tool-versions`.

```sh
mix setup
mix zipfelfolio.create_user you@example.com
mix phx.server
```

Open http://localhost:4000, ask for a sign-in link and find it at http://localhost:4000/dev/mailbox.
In the settings you can then add a passkey. There is no sign-up and there are no passwords.

The countries and sectors of the funds and the announced dividends come from DivvyDiary's API, which needs a key in
the environment variable `DIVVYDIARY_API_KEY`; without it the holdings and security pages show no regions and
sectors, and the dividend calendar uses the dividends last fetched, or the booked ones if none were ever fetched.

Click dummy:

```sh
python3 -m http.server 8077 --directory mockup
```

## Before you use this

- This is a personal project, built for my own household (1–2 people, a few portfolios).
- I don't accept pull requests (benevolent dictator and all that), but forks are very welcome.

## Stack

Elixir, Phoenix LiveView, SQLite, felt-css, Chart.js; one container behind a reverse proxy.

## License

Public domain ([The Unlicense](LICENSE)). The FI forecast is inspired by
[Beyond Rule 4](https://github.com/JackMorrissey/beyond-rule-4) (MIT).
