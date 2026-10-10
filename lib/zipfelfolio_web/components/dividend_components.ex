defmodule ZipfelfolioWeb.DividendComponents do
  @moduledoc "How the screens show a dividend, see `Dividends.upcoming/4`."
  use Phoenix.Component

  use ZipfelfolioWeb, :verified_routes

  alias ZipfelfolioWeb.Format

  attr :kind, :atom, required: true, values: [:announced, :forecast]
  attr :class, :any, default: nil

  def kind_tag(assigns) do
    ~H"""
    <span class={["badge app-kind", "app-upcoming-#{@kind}", @class]}>{kind_label(@kind)}</span>
    """
  end

  def kind_label(:announced), do: "angekündigt"
  def kind_label(:forecast), do: "Prognose"

  @doc "The `amount` (`:gross` or `:net`) of `dividend` in euros, with „~“ for a forecast."
  def expected(%{kind: :forecast} = dividend, amount, places),
    do: "~" <> Format.euros(dividend[amount], places)

  def expected(dividend, amount, places), do: Format.euros(dividend[amount], places)

  @doc "The total `amount` of `dividends` in euros, with „~“ as soon as a forecast counts."
  def expected_total(dividends, amount, places) do
    total = dividends |> Enum.sum_by(& &1[amount]) |> Format.euros(places)
    if Enum.any?(dividends, &(&1.kind == :forecast)), do: "~" <> total, else: total
  end

  attr :gross, :boolean, default: false, doc: "whether the amounts are before taxes"

  def forecast_note(assigns) do
    currencies = if assigns.gross, do: "Vor Steuern, Fremdwährungen", else: "Fremdwährungen"
    assigns = assign(assigns, currencies: currencies)

    ~H"""
    Angekündigt sind Termine von DivvyDiary. Die Prognose nimmt die Zahlungen der letzten
    12 Monate ein Jahr später, mal heutigem Bestand. {@currencies} zum letzten EZB‑Kurs.
    """
  end

  attr :security, :map, required: true, doc: "nil for a dividend booked without a security"
  attr :class, :string, default: nil

  def security_link(%{security: nil} = assigns) do
    ~H"""
    <span class={["d-block fw-semibold text-body-secondary", @class]}>Ohne Wertpapier</span>
    """
  end

  def security_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/securities/#{@security}"}
      class={["d-block fw-semibold text-body text-decoration-none", @class]}
    >
      {security_name(@security)}
    </.link>
    """
  end

  @doc "Names such as „All-World“ never break at their hyphen."
  def security_name(security), do: String.replace(security.name, "-", "\u2011")
end
