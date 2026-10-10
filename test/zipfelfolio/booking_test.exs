defmodule Zipfelfolio.BookingTest do
  use Zipfelfolio.DataCase

  import Zipfelfolio.{PortfoliosFixtures, SecuritiesFixtures, UsersFixtures}

  alias Zipfelfolio.{LocalTime, Portfolios, PPImport, Valuation}
  alias Zipfelfolio.Portfolios.{Receipt, Transaction}
  alias Zipfelfolio.Valuation.Market

  @day ~D[2026-10-01]

  setup do
    scope = user_scope_fixture()
    account = account_fixture(scope, name: "Verrechnungskonto")
    portfolio = portfolio_fixture(scope, reference_account_id: account.id)
    security = security_fixture()

    %{
      scope: scope,
      account: account,
      portfolio: portfolio,
      security: security,
      choices: Portfolios.transaction_choices(scope)
    }
  end

  defp form(ctx, kind, attrs) do
    Map.merge(
      %{
        "kind" => kind,
        "date" => Date.to_iso8601(@day),
        "portfolio_id" => ctx.portfolio.id,
        "security_id" => ctx.security.id,
        "account_id" => ctx.account.id
      },
      attrs
    )
  end

  defp book(ctx, kind, attrs, receipt \\ nil),
    do: Portfolios.book_transaction(ctx.scope, ctx.choices, form(ctx, kind, attrs), receipt)

  defp booked(transaction) do
    transaction = Repo.preload(transaction, :units, force: true)

    transaction
    |> Map.take([:type, :portfolio_id, :account_id, :security_id, :shares, :amount, :currency])
    |> Map.put(:units, Enum.map(transaction.units, &{&1.type, &1.amount}))
  end

  # Holdings, account balances and invested capital at the end of the day.
  defp figures(ctx) do
    transactions = Portfolios.list_transactions(ctx.scope)
    market = Market.new([ctx.security], [], [])

    [%{invested_capital: invested}] =
      Valuation.history(transactions, Portfolios.list_accounts(ctx.scope), market, [@day])

    %{
      holdings: for(h <- Valuation.holdings(transactions, @day), do: {h.portfolio_id, h.shares}),
      balances: Valuation.balances(transactions, @day),
      invested_capital: invested
    }
  end

  describe "the amount" do
    test "follows shares and price with fees", ctx do
      changeset =
        Portfolios.change_transaction_form(
          ctx.scope,
          ctx.choices,
          form(ctx, "purchase", %{"shares" => "10", "price" => "100,0000", "fees" => "1,00"})
        )

      assert Decimal.equal?(get_field(changeset, :amount), "1001.00")
      assert get_field(changeset, :expected_amount) == nil
    end

    test "warns when overwritten far from shares × price, and still books", ctx do
      attrs = %{
        "shares" => "31,0700",
        "price" => "12,0699",
        "amount" => "375,02",
        "amount_set" => "true"
      }

      changeset =
        Portfolios.change_transaction_form(ctx.scope, ctx.choices, form(ctx, "purchase", attrs))

      assert Decimal.equal?(get_field(changeset, :expected_amount), "375.01")
      assert changeset.valid?

      assert {:ok, [transaction]} = book(ctx, "purchase", attrs)
      assert transaction.amount == 37_502
    end

    test "overwritten within the rounding of a four-decimal price does not warn", ctx do
      attrs = %{
        "shares" => "31,07",
        "price" => "12,0699",
        "amount" => "375,01",
        "amount_set" => "true"
      }

      changeset =
        Portfolios.change_transaction_form(ctx.scope, ctx.choices, form(ctx, "purchase", attrs))

      assert get_field(changeset, :expected_amount) == nil
    end
  end

  describe "book_transaction/4 books as the PP import would" do
    test "a purchase from an account", ctx do
      attrs = %{"shares" => "10", "price" => "100", "fees" => "4,50", "taxes" => "1"}
      assert {:ok, [purchase]} = book(ctx, "purchase", attrs)

      assert booked(purchase) == %{
               type: :buy,
               portfolio_id: ctx.portfolio.id,
               account_id: ctx.account.id,
               security_id: ctx.security.id,
               shares: shares(10),
               amount: money(1_005.50),
               currency: "EUR",
               units: [fee: 450, tax: 100]
             }

      assert %Transaction{source: :manual, date_time: ~N[2026-10-01 00:00:00]} = purchase

      assert figures(ctx) == %{
               holdings: [{ctx.portfolio.id, shares(10)}],
               balances: %{ctx.account.id => -money(1_005.50)},
               invested_capital: 0
             }
    end

    test "a purchase without an account as an inbound delivery", ctx do
      attrs = %{"shares" => "10", "price" => "100", "account_id" => ""}
      assert {:ok, [delivery]} = book(ctx, "purchase", attrs)

      assert %{type: :inbound_delivery, account_id: nil, amount: 100_000} = booked(delivery)

      assert figures(ctx) == %{
               holdings: [{ctx.portfolio.id, shares(10)}],
               balances: %{},
               invested_capital: money(1_000)
             }
    end

    test "a sale into an account, and without one as an outbound delivery", ctx do
      {:ok, _} = book(ctx, "purchase", %{"shares" => "10", "price" => "100", "account_id" => ""})
      attrs = %{"shares" => "4", "price" => "105", "fees" => "4,50", "taxes" => "3,20"}
      assert {:ok, [sale]} = book(ctx, "sale", attrs)

      assert booked(sale) == %{
               type: :sell,
               portfolio_id: ctx.portfolio.id,
               account_id: ctx.account.id,
               security_id: ctx.security.id,
               shares: shares(4),
               amount: money(412.30),
               currency: "EUR",
               units: [fee: 450, tax: 320]
             }

      attrs = %{"shares" => "1", "price" => "105", "account_id" => ""}
      assert {:ok, [delivery]} = book(ctx, "sale", attrs)
      assert %{type: :outbound_delivery, account_id: nil, amount: 10_500} = booked(delivery)

      assert figures(ctx) == %{
               holdings: [{ctx.portfolio.id, shares(5)}],
               balances: %{ctx.account.id => money(412.30)},
               invested_capital: money(1_000 - 105)
             }
    end

    test "a dividend on the account, without a portfolio side", ctx do
      attrs = %{"shares" => "40", "gross" => "100", "taxes" => "18,50"}
      assert {:ok, [dividend]} = book(ctx, "dividend", attrs)

      assert booked(dividend) == %{
               type: :dividend,
               portfolio_id: nil,
               account_id: ctx.account.id,
               security_id: ctx.security.id,
               shares: shares(40),
               amount: money(81.50),
               currency: "EUR",
               units: [tax: 1_850]
             }

      assert figures(ctx).balances == %{ctx.account.id => money(81.50)}
    end

    test "a deposit and a removal", ctx do
      assert {:ok, [deposit]} = book(ctx, "deposit", %{"amount" => "1.000,00"})
      assert {:ok, [removal]} = book(ctx, "removal", %{"amount" => "250"})

      assert %{type: :deposit, portfolio_id: nil, security_id: nil, amount: 100_000, units: []} =
               booked(deposit)

      assert %{type: :removal, account_id: account_id, amount: 25_000} = booked(removal)
      assert account_id == ctx.account.id

      assert figures(ctx) == %{
               holdings: [],
               balances: %{ctx.account.id => money(750)},
               invested_capital: money(750)
             }
    end
  end

  test "a dividend removed at once books the dividend and a removal of its amount", ctx do
    attrs = %{"gross" => "100,00", "taxes" => "18,50", "remove_at_once" => "true"}
    assert {:ok, [dividend, removal]} = book(ctx, "dividend", attrs)

    assert %{type: :dividend, amount: 8_150} = booked(dividend)

    assert %{type: :removal, account_id: account_id, security_id: nil, amount: 8_150, units: []} =
             booked(removal)

    assert account_id == ctx.account.id
    assert removal.date_time == dividend.date_time
    assert removal.id != dividend.id
    assert figures(ctx).balances == %{ctx.account.id => 0}
  end

  describe "checks" do
    test "no sale beyond the holding on its day", ctx do
      {:ok, _} = book(ctx, "purchase", %{"shares" => "5", "price" => "100"})

      later = %{"date" => "2026-10-02", "shares" => "1", "price" => "100"}
      {:ok, _} = book(ctx, "purchase", later)

      assert {:error, changeset} = book(ctx, "sale", %{"shares" => "6", "price" => "100"})
      assert errors_on(changeset).shares == ["übersteigt den Bestand von 5 Stück"]

      assert {:ok, _} = book(ctx, "sale", %{"shares" => "5", "price" => "100"})
    end

    test "required fields per type", ctx do
      empty = %{"date" => "2026-10-01", "portfolio_id" => "", "account_id" => ""}

      {:error, purchase} =
        Portfolios.book_transaction(ctx.scope, ctx.choices, Map.put(empty, "kind", "purchase"))

      assert sorted_keys(errors_on(purchase)) == [
               :amount,
               :portfolio_id,
               :price,
               :security_id,
               :shares
             ]

      {:error, dividend} =
        Portfolios.book_transaction(ctx.scope, ctx.choices, Map.put(empty, "kind", "dividend"))

      assert sorted_keys(errors_on(dividend)) == [:account_id, :amount, :gross, :security_id]

      {:error, deposit} =
        Portfolios.book_transaction(ctx.scope, ctx.choices, Map.put(empty, "kind", "deposit"))

      assert sorted_keys(errors_on(deposit)) == [:account_id, :amount]
    end

    test "no date in the future", ctx do
      tomorrow = LocalTime.today() |> Date.add(1) |> Date.to_iso8601()
      assert {:error, changeset} = book(ctx, "deposit", %{"amount" => "1", "date" => tomorrow})
      assert errors_on(changeset).date == ["darf nicht in der Zukunft liegen"]
    end

    test "only the user's own portfolios and accounts", ctx do
      other = user_scope_fixture()
      foreign = account_fixture(other)

      assert {:error, changeset} =
               book(ctx, "deposit", %{"amount" => "1", "account_id" => foreign.id})

      assert errors_on(changeset).account_id == ["ist ungültig"]
    end

    test "only accounts in euros", ctx do
      dollars = account_fixture(ctx.scope, name: "Dollarkonto", currency: "USD")
      choices = Portfolios.transaction_choices(ctx.scope)
      refute dollars in choices.accounts

      assert {:error, changeset} =
               Portfolios.book_transaction(
                 ctx.scope,
                 choices,
                 form(ctx, "deposit", %{"amount" => "1", "account_id" => dollars.id})
               )

      assert errors_on(changeset).account_id == ["ist ungültig"]
    end

    test "amounts in whole cents", ctx do
      assert {:error, changeset} = book(ctx, "deposit", %{"amount" => "1,005"})
      assert errors_on(changeset).amount == ["hat höchstens 2 Nachkommastellen"]
    end

    test "no absurdly large numbers", ctx do
      huge = "1e30"

      assert {:error, purchase} =
               book(ctx, "purchase", %{"shares" => huge, "price" => huge, "fees" => huge})

      assert %{shares: [_], price: [_], fees: [_], amount: ["must be less than 1000000000"]} =
               errors_on(purchase)

      assert {:error, dividend} = book(ctx, "dividend", %{"gross" => huge, "taxes" => huge})
      assert %{gross: [_], taxes: [_]} = errors_on(dividend)

      assert {:error, deposit} = book(ctx, "deposit", %{"amount" => huge})
      assert errors_on(deposit).amount == ["must be less than 1000000000"]
      assert Portfolios.list_transactions(ctx.scope) == []
    end
  end

  defp sorted_keys(map), do: map |> Map.keys() |> Enum.sort()

  describe "receipts" do
    @pdf "%PDF-1.4\nein Beleg\n%%EOF\n"

    setup do
      path = Path.join(System.tmp_dir!(), "receipt-#{System.unique_integer([:positive])}.pdf")
      File.write!(path, @pdf)
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    test "are stored once per file and attached to the transaction", ctx do
      assert {:ok, [first]} = book(ctx, "deposit", %{"amount" => "1"}, {ctx.path, "a.pdf"})
      assert {:ok, [second]} = book(ctx, "deposit", %{"amount" => "2"}, {ctx.path, "b.pdf"})

      assert first.receipt_id == second.receipt_id
      receipt = Repo.get!(Receipt, first.receipt_id)
      assert %{filename: "a.pdf", byte_size: 25, user_id: user_id} = receipt
      assert user_id == ctx.scope.user.id
      assert receipt.sha256 == Base.encode16(:crypto.hash(:sha256, @pdf), case: :lower)
      assert File.read!(Portfolios.receipt_file(receipt)) == @pdf
    end

    test "attach to the dividend, not to its removal", ctx do
      attrs = %{"gross" => "10", "remove_at_once" => "true"}
      assert {:ok, [dividend, removal]} = book(ctx, "dividend", attrs, {ctx.path, "d.pdf"})
      assert dividend.receipt_id
      assert removal.receipt_id == nil
    end

    test "must be PDFs", ctx do
      File.write!(ctx.path, "kein PDF")

      assert {:error, changeset} =
               book(ctx, "deposit", %{"amount" => "1"}, {ctx.path, "x.pdf"})

      assert errors_on(changeset).receipt == ["ist keine PDF-Datei"]
      assert Portfolios.list_transactions(ctx.scope) == []
    end
  end

  test "a PP re-import keeps manually booked transactions", ctx do
    {:ok, _} = PPImport.run(ctx.scope, "test/fixtures/pp/sample.portfolio")
    {:ok, [deposit]} = book(ctx, "deposit", %{"amount" => "100"})

    {:ok, _} = PPImport.run(ctx.scope, "test/fixtures/pp/sample.portfolio")

    assert Repo.get(Transaction, deposit.id)
  end
end
