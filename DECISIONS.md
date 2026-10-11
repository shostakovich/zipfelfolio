# Decisions

## 0001. One transaction per business event

Accepted, 2026-10-08

PP keeps a purchase in memory as two linked entries (portfolio and account), but its protobuf file stores it
as one `PTransaction` with `other*` fields. zipfelfolio follows the file: one transaction with a portfolio side,
an account side or both. The import maps one record to one record, both sides can never drift apart, and the
booking form edits one thing. Calculations that need a per-side view derive it.

## 0002. Compute holdings on every request

Accepted, 2026-10-09

- **Context:** Overview, holdings and charts need holdings and values for any date. A household has at most a few
  thousand transactions and a handful of securities, and a booking, a re-import or a price fix can change any
  past date.
- **Decision:** A pure module computes holdings and values from transactions and prices on every request; no
  stored daily snapshots.
- **Consequences:** Nothing to invalidate or rebuild after a change. Every page load repeats the work, so a much
  longer history would need caching or snapshots later.

## 0003. Recognise receipts locally from their text

Accepted, 2026-10-10

- **Context:** Bank receipts carry account numbers and amounts, and the owner wants them to stay on the home
  server. The plan of 2026-10-07 sent the PDF to the Claude API to avoid extracting and redacting text first.
- **Decision:** zipfelfolio sends the receipt's text (Paperless' `content`, else `pdftotext`) to any
  OpenAI-compatible chat API with a JSON schema, such as Ollama on the home server; not the Claude API with the PDF.
- **Consequences:** No receipt leaves the house and any local or hosted model fits. Scanned receipts without a text
  layer depend on Paperless' OCR, a CPU-bound model takes about a minute per receipt, and the image needs
  poppler-utils.

## 0004. Paperless access per user

Accepted, 2026-10-10

- **Context:** Receipts belong to the user whose portfolio they concern; one Paperless instance may serve several
  of a user's portfolios, and other users may have their own instance or none.
- **Decision:** Each user enters Paperless URL, token and tag in the settings; not one global connection in the
  environment.
- **Consequences:** Ownership is clear without guessing from depot numbers and nothing needs a redeploy. The
  token lives in the database, so a database backup grants access to Paperless. Any signed-in user can make the
  server call the URL they enter, which is acceptable for a self-hosted app with trusted users and no
  self-registration.

## 0005. The UI is built on setzkasten, Tailwind and daisyUI

Accepted, 2026-10-11

- **Context:** The author's Phoenix apps have the same kind of backend screens, and each one styling its own
  buttons, tables, dialogs and navigation drifts apart and repeats the work.
- **Decision:** Tailwind 4 and daisyUI 5 as `phx.new` 1.8 sets them up, with the components and themes of the
  shared library setzkasten (`use Setzkasten`) and its design rules: flat pages, cards only for independent objects,
  every irreversible delete confirmed in one shared dialog. Only zipfelfolio's own styles live in
  `assets/css/app.css`.
- **Consequences:** The asset build needs the Tailwind binary and setzkasten is a dependency. daisyUI is a sparse
  git Mix dependency pinned to a tag in `mix.exs`, not the file `phx.new` vendors into `assets/vendor`. A component the
  other apps could use goes into the library, not into the app. LiveView tests confirm deletes through
  `ConfirmHelpers`, as the dialog parks the event in the browser.
