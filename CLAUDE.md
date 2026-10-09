# CLAUDE.md – zipfelfolio

Self-hosted portfolio tracker; scope and decisions live in the GitHub issues, one spec per issue. The deploy
runbook lives in Outline (zipfelfolio hub), not in the repo. UI text is German; code, comments and docs
English, sparse comments.

## Validation

```
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
```

CI runs the same plus `mix assets.deploy`. Erlang/Elixir versions: `.tool-versions`.

## Conventions

- Schemas `use Zipfelfolio.Schema` (`:utc_datetime_usec` timestamps). Migrations are recorded in
  production: add new ones, leave old ones as they are; releases run them via `Release.migrate/0`.
- DB tests run synchronously with `pool_size: 1` (SQLite is busy otherwise).
- Context functions take `%Scope{}`: a user sees only their own portfolios, accounts and transactions; nothing is
  shared between users except securities and prices.
- UI: felt-css with Bootstrap class names via `core_components`. A felt.css bug becomes an issue in
  `shostakovich/felt-css`, the app keeps plain Bootstrap markup.
- Passkeys (`Zipfelfolio.WebAuthn`) check origin and RP ID from the endpoint URL, so they work on
  `localhost` and `https://folio.rocu.de`, not on a LAN IP. Every check has a breaking test in
  `test/zipfelfolio/web_authn_test.exs` using `FakeAuthenticator`; a new check gets one too.
- Dependencies: few and mature, each with a reason.
- `github-profil/` in the checkout is unrelated and stays out of commits.
