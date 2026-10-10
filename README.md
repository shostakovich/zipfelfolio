# zipfelfolio

A self-hosted portfolio tracker for one household: holdings, performance, dividends (history, calendar,
forecast) and a savings plan. It is meant to replace [Portfolio Performance](https://www.portfolio-performance.info/)
and a [DivvyDiary](https://divvydiary.com/) subscription. **The user interface is German.**

## Status

Built so far: the import of a Portfolio Performance file, prices from Yahoo and ECB exchange rates fetched daily,
the overview (net worth, its chart, TTWROR, IRR, dividends with the next ones), the performance screen (TTWROR, IRR,
drawdown and volatility, the breakdown of the change in value, monthly returns as a heatmap), a benchmark of the
user's choice (its TTWROR beside the portfolios' and a shadow portfolio in it on the overview's chart), the holdings
with costs, allocation and dividend yield, a page per security with its next payments, the dividends received per
month and year with a calendar of the coming ones, the dialog to book purchases, sales, dividends, deposits and
removals with a PDF receipt, new securities by ISIN, and the transactions screen to edit and delete them with an
inbox for receipts from Paperless-ngx or uploaded that a local language model reads and matches to a portfolio by
its depot number; sign-in with passkeys or a link by email, container
and deploy.

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

Receipts are read by any OpenAI-compatible chat API, such as Ollama or LM Studio on your own server:
`RECEIPT_MODEL_URL` (e.g. `http://localhost:11434/v1`), `RECEIPT_MODEL` and, if the API wants one,
`RECEIPT_MODEL_KEY`. The text comes from Paperless or else from `pdftotext` (poppler). Without a model a receipt
still lands in the inbox and opens an empty form. A thinking model (Qwen 3, Gemma 4) is asked not to think, with
`reasoning_effort: "none"`, which Ollama and LM Studio both understand; `RECEIPT_MODEL_THINKING=on` lets it think.
LM Studio constrains the answer to the JSON schema from the first token, so its models never think there anyway.
Each user enters their Paperless-ngx URL, API token and tag under Einstellungen › Belegeingang; every 15 minutes the
documents with that tag go into the inbox and get the tag „<tag>-erledigt“ instead.

To choose a model, measure the candidates on real receipts: put the PDFs into `test/fixtures/receipts/private/`,
which git ignores, in a checkout on a machine that reaches the home server's Ollama. Bootstrap an expected file per
receipt from the most trusted model, then correct every `<name>.expected.json` by hand:

```sh
mix zipfelfolio.measure_receipts --url http://homeserver:11434/v1 --model gemma4:26b --write-expected
```

Then compare the candidates, with and without thinking (`ollama list` shows the exact tags):

```sh
mix zipfelfolio.measure_receipts --url http://homeserver:11434/v1 --thinking both \
  --model gemma4:e2b --model gemma4:e4b --model gemma4:12b --model gemma4:26b --json measurement.json
```

The table shows per model the share of each field read right, as the inbox uses it, and the seconds per receipt;
below it, the wrong fields per receipt. Like the inbox, the model gets one more round when the amount does not add
up, shares, price or amount are missing or the ISIN is invalid; `--correction both` measures with and without it, and the table counts the rounds, those
that fixed the checks and the answers with values not in the receipt's text. `test/fixtures/receipts/synthetic/` holds made-up receipts to try it
without real ones. For more banks' layouts, `--fetch-pp comdirect,scalablecapital,dkb,onvista` fetches Portfolio
Performance's anonymised importer test texts with expected fields from its test asserts into
`test/fixtures/receipts/pp/`, which git ignores as they are EPL-licensed; measure them with that folder and
`--sample 15`. Their price, depot number and reference are not scored.

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
