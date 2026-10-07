# zipfelfolio

A self-hosted portfolio tracker for one household: holdings, performance, dividends (history, calendar,
forecast) and a savings plan. It is meant to replace [Portfolio Performance](https://www.portfolio-performance.info/)
and a [DivvyDiary](https://divvydiary.com/) subscription. **The user interface is German.**

## Status

Planning. Nothing to install yet.

- [docs/SPEC.md](docs/SPEC.md): scope, domain, data sources, phases
- `mockup/`: click dummy with example data, built with [felt-css](https://felt-css.rocu.de/)

```sh
python3 -m http.server 8077 --directory mockup
```

## Before you use this

- This is a personal project, built for my own household (1–2 people, a few portfolios).
- I don't accept pull requests (benevolent dictator and all that), but forks are very welcome.

## Planned stack

Elixir, Phoenix LiveView, SQLite, felt-css; one container behind a reverse proxy.

## License

Public domain ([The Unlicense](LICENSE)). The FI forecast is inspired by
[Beyond Rule 4](https://github.com/JackMorrissey/beyond-rule-4) (MIT).
