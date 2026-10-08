# One transaction per business event

PP keeps a purchase in memory as two linked entries (portfolio and account), but its protobuf file stores it
as one `PTransaction` with `other*` fields. zipfelfolio follows the file: one transaction with a portfolio side,
an account side or both. The import maps one record to one record, both sides can never drift apart, and the
booking form edits one thing. Calculations that need a per-side view derive it.
