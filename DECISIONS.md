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
