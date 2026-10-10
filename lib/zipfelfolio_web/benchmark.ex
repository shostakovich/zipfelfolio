defmodule ZipfelfolioWeb.Benchmark do
  @moduledoc """
  Showing or hiding the user's benchmark on the overview and the performance screen, a choice of
  the device like the collapsed sidebar: hidden by default, the browser keeps the choice and sends
  it when a page connects (`assets/js/benchmark.js`). An `on_mount` hook assigns it as
  `@benchmark_shown` and handles the button's `"toggle_benchmark"`.
  """
  use Phoenix.Component

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, get_connect_params: 1, push_event: 3]

  alias ZipfelfolioWeb.Format

  def on_mount(:default, _params, _session, socket) do
    shown = connected?(socket) and get_connect_params(socket)["benchmark"] == "shown"

    {:cont,
     socket
     |> assign(:benchmark_shown, shown)
     |> attach_hook(:benchmark, :handle_event, &toggle/3)}
  end

  defp toggle("toggle_benchmark", _params, socket) do
    shown = not socket.assigns.benchmark_shown

    {:halt,
     socket
     |> assign(:benchmark_shown, shown)
     |> push_event("benchmark", %{shown: shown})}
  end

  defp toggle(_event, _params, socket), do: {:cont, socket}

  attr :shown, :boolean, required: true

  @doc "The button „Benchmark“ that shows or hides the benchmark."
  def toggle_button(assigns) do
    ~H"""
    <button
      type="button"
      id="benchmark-toggle"
      class={["btn btn-sm btn-outline-secondary app-benchmark-toggle", @shown && "active"]}
      aria-pressed={to_string(@shown)}
      phx-click="toggle_benchmark"
    >
      <span class="app-benchmark-key" aria-hidden="true"></span> Benchmark
    </button>
    """
  end

  attr :benchmark, :map, required: true, doc: "`%{security, ttwror}`"

  @doc "The benchmark's TTWROR and name, the name cut short when it does not fit."
  def note(assigns) do
    ~H"""
    <span id="benchmark-ttwror" class="app-benchmark-note">
      <span class="visually-hidden">Benchmark:</span>
      <span class="text-nowrap tabular-nums app-benchmark-ttwror">
        <span class="app-benchmark-key" aria-hidden="true"></span>{ttwror(@benchmark.ttwror)}
      </span>
      <span class="app-benchmark-name" title={@benchmark.security.name}>
        {short_name(@benchmark.security.name)}
      </span>
    </span>
    """
  end

  attr :security, :map, required: true

  @doc """
  The key of the shadow portfolio's line on the net worth chart, on the phone „Benchmark“ as on
  the button, so that all keys fit one row.
  """
  def legend(assigns) do
    ~H"""
    <span id="benchmark-legend" class="app-benchmark-legend" title={@security.name}>
      <span class="app-swatch app-swatch-benchmark"></span>
      <span class="d-none d-sm-inline">{short_name(@security.name)}</span>
      <span class="d-sm-none">Benchmark</span>
    </span>
    """
  end

  @doc """
  The name without what most fund names end with, such as „UCITS ETF USD (Acc)“, a last „ETF“
  with its currency or „(Dist)“, so that a note shows the part that tells funds apart.
  """
  def short_name(name) do
    suffix = ~r/\s+(UCITS\b.*|ETF(\s+(?-i:[A-Z]{3}))?(\s+\([^()]*\))?|\([^()]*\))$/i

    case name |> String.replace(suffix, "") |> String.trim() do
      "" -> name
      short -> short
    end
  end

  defp ttwror(nil), do: "–"
  defp ttwror(rate), do: rate |> Kernel.*(100) |> Decimal.from_float() |> Format.signed_percent(2)
end
