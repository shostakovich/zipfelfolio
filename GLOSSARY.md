# zipfelfolio

Self-hosted portfolio tracker for one household. Replaces Portfolio Performance (PP) and DivvyDiary.

## People

**User** · _de:_ Person
- A person who signs in. Portfolios, accounts and taxonomies belong to a user; securities and prices are shared by
  all users.
- _Avoid:_ Account (that is a cash account)

## Holdings

**Security** · _de:_ Wertpapier
- A tradable instrument (ETF, fund, share) identified by its ISIN, with its own price history.
- _Avoid:_ Asset, instrument, position

**Portfolio** · _de:_ Depot
- A securities account at a bank; it holds shares of securities.
- _Avoid:_ Securities account, depot (in code)

**Account** · _de:_ Konto
- A cash account in one currency. It exists on its own, not as part of a portfolio.
- _Avoid:_ Cash account, Verrechnungskonto (in code)

**Reference account** · _de:_ Referenzkonto
- The account a portfolio's purchases, sales and dividends settle against by default. Several portfolios may share
  one; a portfolio may have none.

**Holding** · _de:_ Position
- The shares of one **Security** in one **Portfolio** on a date, with their value and **Purchase value**. The
  holdings screen ("Bestand") lists them.
- _Example:_ "10 shares of the All-World ETF in the long-term portfolio, worth 1,000 €"
- _Avoid:_ position (in code)

## Valuation

**Net worth** · _de:_ Vermögen
- The value of all of a **User**'s **Holdings** plus the balances of their **Accounts** on a date, in euros.

**Invested capital** · _de:_ Investiert
- What came in from outside up to a date: deposits − removals + inbound deliveries − outbound deliveries, as in PP.
  A purchase from an **Account** moves money inside and changes nothing.
- _Example:_ "Deposit 1,000 € and buy shares for 1,000 € from that account: 1,000 € invested, not 2,000 €"

**Purchase value** · _de:_ Einstand
- What the shares of a **Holding** cost by FIFO, including the fees and taxes of their purchases. The gain is the
  value minus the purchase value.
- _Example:_ "Bought 10 for 1,000 €, then 10 for 1,200 € plus 10 € fee, sold 15: the remaining 5 have a purchase
  value of 605 €"

## Bookings

**Transaction** · _de:_ Buchung
- One business event, such as a purchase, a dividend or a transfer, with a portfolio side, an account side or both.
  A purchase is one transaction, not a security entry plus a cash entry.
- _Avoid:_ Booking, entry, cross entry

**Unit** · _de:_ Bruttobetrag, Gebühr, Steuer
- A part of a transaction's amount: gross value, fee or tax, possibly in a foreign currency with its exchange rate.

**Savings plan** · _de:_ Sparplan
- A recurring purchase, deposit, removal or interest payment with a start, an interval and an amount; it knows the
  transactions it produced.
- _Avoid:_ Investment plan

## Classification

**Taxonomy** · _de:_ Klassifizierung
- A user's named tree of classifications, such as regions or asset allocation.

**Classification** · _de:_ Kategorie
- A node in a taxonomy with a colour and a target weight.
- _Avoid:_ Category, bucket

**Assignment** · _de:_ Zuordnung
- A weighted link from a security or an account to a classification.

**Composition** · _de:_ Zusammensetzung
- A fund's shares per country and per sector, as DivvyDiary reports them. Not an **Assignment**, which the **User**
  sets in a **Taxonomy**.
- _Example:_ "All-World: about 60 % USA"
- _Avoid:_ Look-through, weighting

**Allocation** · _de:_ Aufteilung
- The shares of **Net worth** per region, per sector or per **Classification**, compared with target weights. Regions
  and sectors come from the **Compositions** of the held funds.
