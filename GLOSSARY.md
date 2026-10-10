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

**Distribution** · _de:_ Ausschüttung
- What a **Security** paid per share on a payment date, from the **User**'s dividend transactions: their gross
  value before taxes and fees per share, in the security's currency where PP knows the gross value in it, else
  in the payment's.
- _Example:_ "0,50 USD per share on 30 September, for 40 shares"

## Performance

**Benchmark** · _de:_ Benchmark
- The **Security** a **User** compares their portfolios with, such as an MSCI ACWI ETF. Each user picks their own,
  or none.

**Shadow portfolio** · _de:_ Schattendepot
- What the **User**'s money would be worth in the **Benchmark**: it starts with the **Net worth** of the chart's
  first day, and every deposit, removal or delivery buys or sells benchmark shares that day.
- _Example:_ "1,000 € at 100 €, then 500 € deposited at 125 €, benchmark now at 150 €: 2,100 €"

## Dividends

**Dividend** · _de:_ Dividende
- What a **User** receives or will receive for their shares of a **Security** on a pay date. Unlike a
  **Distribution**, which is per share, it is the user's amount.
- _Avoid:_ Payment

**Announced dividend** · _de:_ angekündigt
- A future **Dividend** that DivvyDiary has announced with ex date and pay date.

**Forecast dividend** · _de:_ Prognose
- A future **Dividend** projected from what the **Security** paid per share in the last 12 months, moved one year
  later, times today's shares; only after its last **Announced dividend**.

**Net dividend** · _de:_ Netto
- A **Dividend**'s gross value minus taxes and fees, what reaches the account. For a future one it is estimated
  from the ratio of net to gross over the **User**'s dividends of the last 12 months.
- _Example:_ "100 € gross, 18.50 € tax: 81.50 € net"

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
- The shares of the shown securities' value per region or per sector, or of the assigned value per top-level
  **Classification**, compared with its target weight. Regions and sectors come from the **Compositions** of the held
  funds; accounts do not count, and securities without one are „Ohne Angabe“. The shares of the classifications
  refer to the value assigned in their **Taxonomy**, as their target weights do; the rest is „Ohne Kategorie“.
