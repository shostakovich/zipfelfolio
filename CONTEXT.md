# zipfelfolio

Self-hosted portfolio tracker for one household. Replaces Portfolio Performance (PP) and DivvyDiary.

## Language

### People

**User**:
A person who signs in. Portfolios, accounts and taxonomies belong to a user; securities and prices are shared by all users.
_German UI_: Person
_Avoid_: Account (that is a cash account)

### Holdings

**Security**:
A tradable instrument (ETF, fund, share) identified by its ISIN, with its own price history.
_German UI_: Wertpapier
_Avoid_: Asset, instrument, position

**Portfolio**:
A securities account at a bank; it holds shares of securities.
_German UI_: Depot
_Avoid_: Securities account, depot (in code)

**Account**:
A cash account in one currency. It exists on its own, not as part of a portfolio.
_German UI_: Konto
_Avoid_: Cash account, Verrechnungskonto (in code)

**Reference account**:
The account a portfolio's purchases, sales and dividends settle against by default. Several portfolios may share one; a portfolio may have none.
_German UI_: Referenzkonto

### Bookings

**Transaction**:
One business event, such as a purchase, a dividend or a transfer, with a portfolio side, an account side or both. A purchase is one transaction, not a security entry plus a cash entry.
_German UI_: Buchung
_Avoid_: Booking, entry, cross entry

**Unit**:
A part of a transaction's amount: gross value, fee or tax, possibly in a foreign currency with its exchange rate.
_German UI_: Bruttobetrag, Gebühr, Steuer

**Savings plan**:
A recurring purchase, deposit, removal or interest payment with a start, an interval and an amount; it knows the transactions it produced.
_German UI_: Sparplan
_Avoid_: Investment plan

### Classification

**Taxonomy**:
A user's named tree of classifications, such as regions or asset allocation.
_German UI_: Klassifizierung

**Classification**:
A node in a taxonomy with a colour and a target weight.
_German UI_: Kategorie
_Avoid_: Category, bucket

**Assignment**:
A weighted link from a security or an account to a classification.
_German UI_: Zuordnung
