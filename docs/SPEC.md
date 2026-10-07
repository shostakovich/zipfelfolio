# zipfelfolio — spec

Self-hosted portfolio tracker for one household. Replaces Portfolio Performance (PP) and the DivvyDiary
subscription. Open source, benevolent dictator: no PRs, forks welcome.

The click dummy in `mockup/` shows the intended screens (example data only).

## Scope

- 1–2 users, several portfolios (securities accounts), each with a cash account
- mobile and desktop, one LiveView app
- base currency EUR; securities and dividends may be in other currencies (USD), converted with ECB rates
- runs on the home server behind Caddy at `https://folio.rocu.de`, HTTPS only

Not in scope: Vorabpauschale, Freistellungsauftrag, trading, public hosting, multi-tenant.

## Stack

- Elixir, Phoenix 1.8, LiveView, SQLite (`ecto_sqlite3`), esbuild, one amd64 container
- felt-css (`https://felt-css.rocu.de/felt.css`), Bootstrap class names in `core_components`, clean look by
  default
- Charts: Chart.js as vendored UMD in LiveView hooks
- HTTP: `req`; mail: `swoosh`
- New dependencies only with a reason
- Same conventions as ZiWoAS and FeatherPage: `default_transaction_mode: :immediate`, WAL,
  `:utc_datetime_usec`, synchronous DB tests, `pool_size: 1` in test

## Login

- `phx.gen.auth` magic link as base and recovery; no passwords, no sign-up (invite or mix task)
- Passkeys implemented in-house: `:crypto`, `:public_key`, `JSON`, attestation `none`, no `wax_`
- Register: challenge in session, `residentKey: required`, `userVerification: required`, ES256/Ed25519/RS256;
  verify `clientDataJSON` (type, challenge, origin), `rpIdHash`, flags UP and UV; store credential id, SPKI key
  (`getPublicKey()`), algorithm, sign count, device name
- Sign in: same checks plus signature over `authenticatorData ‖ sha256(clientDataJSON)`; sign count 0 is
  fine (synced passkeys), a decreasing non-zero count is rejected
- Tests fake the authenticator with `:crypto` and break every check once; separate review against
  WebAuthn Level 3 §7.1/§7.2
- Users see portfolios they own or that were shared with them (Phoenix scopes)

## Domain

Mirrors PP so the import is lossless.

- **Security**: name, ISIN, WKN, currency, quote feed + symbol (e.g. Yahoo `VGWL.DE`), dividend feed, retired
  flag, attributes (TER, fund size, provider, …), notes
- **Price**: security, date, close; latest quote cached separately
- **Portfolio**: name, owner, reference account, retired flag
- **Account**: cash account, currency
- **Transaction**: date, type, account and/or portfolio, security, shares, amount, currency, units (fee, tax,
  gross value with FX rate), note, source (manual, PP import, receipt), optional document
  - types as in PP: buy, sell, inbound/outbound delivery, security transfer, deposit, removal, dividend,
    interest, fee, fee refund, tax, tax refund, cash transfer
- **Taxonomy**: classifications with parent, colour, target weight; assignments security → classification
  with weight
- **Dividend event**: security, ex date, pay date, amount per share, currency, source, `announced` flag
- **Exchange rate**: ECB daily reference rates
- **Document**: PDF, SHA-256, origin (upload, Paperless id)
- **Inbox item**: document, extracted transaction, check results, status (open, booked, discarded)
- **Rule** (plan): typed rules with parameters and status

Numbers are integers like in PP: amounts in cents, shares and prices × 10⁸. No floats for money.

## Data sources

All behind a small behaviour per kind, results stored locally; screens never call external APIs.

- **Prices**: Yahoo chart API `query1.finance.yahoo.com/v8/finance/chart/<symbol>` with `period1`/`period2`
  (`range=max` thins out daily data); daily job after Xetra close plus refresh of the latest quote on page
  view, cached ~15 min. Manual prices as fallback.
- **FX**: ECB Data Portal, daily.
- **Dividends, countries, sectors, holdings**: DivvyDiary `GET api.divvydiary.com/symbols/{ISIN}`, header
  `X-API-Key` (`DIVVYDIARY_API_KEY`). Undocumented, used by PP. Returns dividends per share (ex/pay date,
  currency, `forecast` flag), price, country/continent/sector weightings, holdings. Swappable; manual dividend
  events as fallback.
- **Expenses and savings rate** (v4): YNAB API, read only.

## Calculations

- Holdings per date from transactions; value = shares × price, converted to EUR
- TTWROR (daily, cash flows at start of day as PP) per period and annualised; monthly returns heatmap
- IRR (XIRR) per period
- Performance breakdown like PP: start value, price gains, realised gains, earnings, fees, taxes, deposits −
  removals, end value
- Benchmark: TTWROR of a benchmark security (default `IUSQ.DE`, MSCI ACWI) over the same period
- Dividend forecast: announced events × shares at ex date; otherwise repeat the last 12 months' pattern per
  security × current shares; converted with the latest ECB rate; marked as forecast
- Allocation: look-through via DivvyDiary weightings, compared with taxonomy target weights

## PP import

- File is a ZIP with `data.portfolio`: 6-byte header `PPPBV1`, then protobuf `PClient`
  (`name.abuchen.portfolio/src/name/abuchen/portfolio/model/client.proto` in the PP repo)
- Hand-written protobuf wire decoder for the fields we need, no protobuf dependency; do not vendor the
  `.proto` (EPL)
- Imports securities, prices, accounts, portfolios, transactions (with units and cross entries), taxonomies with
  weights, attribute types and values, investment plans
- Repeatable: re-import replaces everything that came from PP, keeps data entered in zipfelfolio; this allows
  running PP in parallel until the switch
- Quote feeds map to Yahoo where possible (`PP` feed → Xetra symbol, e.g. `LDGL.DE`); unmapped ones become
  manual
- XML format only if needed later

## Receipt import (v2)

- Sources: upload (also Web Share Target on Android) and Paperless-ngx (API token, poll by tag, swap tag after
  import); PDF copy is always stored locally
- Extraction: Claude API (`claude-opus-5-5`) with the PDF as document block and structured output (type,
  dates, ISIN, shares, price, gross, fees, taxes, net, currency, FX rate, account/depot number, bank reference)
- Checks in code: arithmetic, ISIN checksum, known depot/account number, duplicate by file hash and bank
  reference
- Result is an inbox item that prefills the booking form; nothing is booked without confirmation
- No port of PP's PDF parsers (EPL)
- Test fixtures: real PDFs from the owner's banks, gitignored

## Screens

- **Overview**: net worth, TTWROR, IRR, dividends this year, value vs. invested vs. benchmark, next
  dividends, portfolios, inbox
- **Dividends**: calendar (announced vs. forecast), per month by year, received
- **Holdings**: per portfolio incl. cash accounts; allocation by region, sector, asset class with targets;
  costs (TER)
- **Security**: price chart with trades, position, distributions per share, profile, data sources
- **Performance**: key figures, breakdown, heatmap, period picker
- **Bookings**: inbox, list with filters, booking form
- **Plan** (v3/v4): rules with status, contributions vs. plan, rebuy calculator, FI forecast
- **Settings**: portfolios and accounts, people, data sources, receipt intake, notifications, interfaces,
  import, look

State that should survive a reload (tab, period, filter, portfolio) lives in the URL.

## Phases

### v1 — replace PP and DivvyDiary

1. Skeleton: Phoenix, SQLite, felt-css `core_components`, login with magic link and passkeys, container,
   deploy behind Caddy, CI (format, credo, tests, assets)
2. PP import
3. Prices and FX jobs, quote feed per security
4. Overview, holdings, security detail
5. Performance incl. benchmark
6. Dividends: history, per month, calendar via DivvyDiary, forecast
7. Booking form

Acceptance: with Robert's PP file (local, gitignored) zipfelfolio shows the same net worth on a given date,
the same TTWROR per year (PP's yearly dashboard) and the same dividends per year as PP.

### v2 — receipts

Receipt import (upload, Claude, Paperless), mail notifications (new inbox item, announced dividend, rule due,
price feed failing), read-only MCP endpoint.

### v3 — plan

Target weights for regions, sectors, asset classes; rebuy calculator (by rule, e.g. 3:1, or largest gap
first); rules with status; contributions vs. plan.

### v4 — outlook

FI forecast after Beyond Rule 4 (MIT; 4 % rule, FI number = 25 × annual expenses, milestones, impact per
expense category) with YNAB data; PWA (manifest, service worker, icons); TRMNL tile.

## Operations

- Data under `/web/data/zipfelfolio` (covered by the existing restic backup), compose under
  `/web/config/zipfelfolio`
- Host `folio.rocu.de` (also the passkey relying party id)
- Config via env: `DIVVYDIARY_API_KEY`, SMTP, `ANTHROPIC_API_KEY` (v2), Paperless URL and token (v2), YNAB
  token (v4), `PHX_HOST`
- `/up` checks DB and that the last price job is younger than 2 days

## Open

- Sample PDFs from the owner's banks (purchase, savings plan execution, distribution)
- Whether a free DivvyDiary account still gets API access (test after cancelling)
