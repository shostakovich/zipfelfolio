defmodule ZipfelfolioWeb.AllocationComponents do
  @moduledoc """
  Bars of an allocation or a composition by region, sector or classification, each with its
  share, as the holdings screen and the security page show them in a card with tabs.
  """
  use Phoenix.Component

  alias ZipfelfolioWeb.Format

  @regions %{
    usa: "USA",
    canada: "Kanada",
    europe: "Europa",
    japan: "Japan",
    pacific_ex_japan: "Pazifik ohne Japan",
    emerging_markets: "Schwellenländer"
  }

  # DivvyDiary names the sectors by GICS, in English.
  @sectors %{
    "Information Technology" => "Technologie",
    "Financials" => "Finanzen",
    "Industrials" => "Industrie",
    "Health Care" => "Gesundheit",
    "Consumer Discretionary" => "Konsum zyklisch",
    "Consumer Staples" => "Basiskonsum",
    "Communication Services" => "Kommunikation",
    "Energy" => "Energie",
    "Materials" => "Grundstoffe",
    "Utilities" => "Versorger",
    "Real Estate" => "Immobilien"
  }

  attr :label, :string, required: true, doc: "what the tabs choose, for screen readers"
  attr :tabs, :list, required: true, doc: "each with its `label`, `path` and whether `active`"

  @doc "Tabs in a card header; each patches the page to its path."
  def card_tabs(assigns) do
    ~H"""
    <nav aria-label={@label}>
      <ul class="nav nav-underline card-header-tabs">
        <li :for={tab <- @tabs} class="nav-item">
          <.link
            patch={tab.path}
            class={["nav-link", tab.active && "active"]}
            aria-current={tab.active && "true"}
          >
            {tab.label}
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  attr :id, :string, required: true

  attr :rows, :list,
    required: true,
    doc: "each with its `key`, see `Allocation.of/2`, and `share`"

  @doc "A bar per region or sector, the largest at full width, „Ohne Angabe“ muted."
  def composition_bars(assigns) do
    assigns = assign(assigns, :scale, bar_scale(Enum.map(assigns.rows, & &1.share)))

    ~H"""
    <ul id={@id} class="list-unstyled d-flex flex-column gap-3 mb-0">
      <li :for={row <- @rows}>
        <div class="d-flex justify-content-between gap-3 small mb-1">
          <span class="fw-semibold">{label(row.key)}</span>
          <span class="tabular-nums text-nowrap">{in_percent(row.share)}</span>
        </div>
        <div class="app-allocation-bar bg-body-tertiary rounded-pill" aria-hidden="true">
          <div
            class={is_nil(row.key) && "app-allocation-unknown"}
            style={"width: #{bar_position(row.share, @scale)}%"}
          >
          </div>
        </div>
      </li>
    </ul>
    """
  end

  @doc "Why there are no regions and sectors: DivvyDiary has no API key."
  def missing_key(assigns) do
    ~H"""
    <p class="text-body-secondary mb-0">
      Für Regionen und Sektoren braucht zipfelfolio einen API-Key von DivvyDiary in der
      Umgebungsvariable <code>DIVVYDIARY_API_KEY</code>. Damit holt der tägliche Abruf um 18:00
      die Länder und Sektoren der Fonds.
    </p>
    """
  end

  @doc "A region, a sector as DivvyDiary names it, or nil for „Ohne Angabe“, in German."
  def label(nil), do: "Ohne Angabe"
  def label(region) when is_atom(region), do: Map.fetch!(@regions, region)
  def label(sector), do: Map.get(@sectors, sector, sector)

  @doc "A fraction in percent with one decimal place."
  def in_percent(fraction), do: fraction |> Decimal.mult(100) |> Format.percent()

  @doc "What fills a bar: the largest of `fractions`, each kept within 0 and 1."
  def bar_scale(fractions),
    do: fractions |> Enum.map(&within_bar/1) |> Enum.max(Decimal, fn -> Decimal.new(0) end)

  @doc """
  A share or a target in percent of the bar that `scale` fills, as CSS; odd targets such as
  −300 % or 400 % are kept within the bar.
  """
  def bar_position(fraction, scale) do
    if Decimal.gt?(scale, 0) do
      fraction
      |> Decimal.div(scale)
      |> within_bar()
      |> Decimal.mult(100)
      |> Decimal.round(1)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
    else
      "0"
    end
  end

  defp within_bar(fraction), do: fraction |> Decimal.max(0) |> Decimal.min(1)
end
