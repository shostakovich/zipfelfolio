defmodule ZipfelfolioWeb.CoreComponents do
  @moduledoc """
  The app's own pieces next to setzkasten's components (`use Setzkasten` in `ZipfelfolioWeb`):
  German error messages, figure tones, gains, the page without portfolios and URL ids.
  """
  use Phoenix.Component
  use ZipfelfolioWeb, :verified_routes

  import Setzkasten.Components.Actions, only: [button: 1]
  import Setzkasten.Components.Data, only: [amount: 1]
  import Setzkasten.Components.Feedback, only: [empty_state: 1]

  alias ZipfelfolioWeb.Format

  @doc """
  The page of a user without portfolios and accounts yet: they come with the import from
  Portfolio Performance.
  """
  def no_portfolios(assigns) do
    ~H"""
    <.empty_state
      layout={:page}
      plush="briefcase"
      icon="briefcase"
      title="Noch keine Depots"
    >
      Depots, Konten und Buchungen kommen mit dem Import aus Portfolio Performance.
      <:action>
        <.button navigate={~p"/settings/import"} variant={:primary} icon="upload">
          Aus Portfolio Performance importieren
        </.button>
      </:action>
    </.empty_state>
    """
  end

  @doc "The class that mutes an amount of zero in a column of amounts."
  def muted(0), do: "text-base-content/70"
  def muted(_amount), do: nil

  @doc "German messages from the validation pass through; Ecto's English ones are looked up."
  @spec translate_error({String.t(), keyword}) :: String.t()
  def translate_error({msg, opts}) do
    # unique_constraint/3 marks its error with `constraint: :unique`, not a validation.
    (Keyword.get(opts, :validation) || Keyword.get(opts, :constraint))
    |> german(msg, opts)
    |> interpolate(opts)
  end

  defp german(:required, "can't be blank", _opts), do: "muss ausgefüllt werden"
  defp german(:inclusion, "is invalid", _opts), do: "ist kein gültiger Wert"
  defp german(:exclusion, "is reserved", _opts), do: "ist nicht erlaubt"
  defp german(:format, "has invalid format", _opts), do: "hat ein ungültiges Format"
  defp german(:cast, "is invalid", _opts), do: "ist ungültig"
  defp german(:unique, "has already been taken", _opts), do: "ist bereits vergeben"
  defp german(:acceptance, "must be accepted", _opts), do: "muss akzeptiert werden"
  defp german(:confirmation, "does not match" <> _, _opts), do: "stimmt nicht überein"

  defp german(:number, "must be " <> _, opts) do
    case Keyword.get(opts, :kind) do
      :less_than -> "muss kleiner als %{number} sein"
      :greater_than -> "muss größer als %{number} sein"
      :less_than_or_equal_to -> "darf höchstens %{number} sein"
      :greater_than_or_equal_to -> "muss mindestens %{number} sein"
      :equal_to -> "muss %{number} sein"
      :not_equal_to -> "darf nicht %{number} sein"
    end
  end

  defp german(:length, "should be " <> _, opts) do
    case {Keyword.get(opts, :type), Keyword.get(opts, :kind)} do
      {:list, :min} -> "braucht mindestens %{count} Einträge"
      {:list, :max} -> "darf höchstens %{count} Einträge haben"
      {:list, :is} -> "braucht genau %{count} Einträge"
      {_, :min} -> "muss mindestens %{count} Zeichen lang sein"
      {_, :max} -> "darf höchstens %{count} Zeichen lang sein"
      {_, :is} -> "muss genau %{count} Zeichen lang sein"
    end
  end

  defp german(_validation, msg, _opts), do: msg

  defp interpolate(msg, opts) do
    Regex.replace(~r/%{(\w+)}/, msg, fn whole, key -> option_text(opts, key, whole) end)
  end

  defp option_text(opts, key, fallback) do
    case Enum.find(opts, fn {name, _} -> Atom.to_string(name) == key end) do
      {_, value} -> to_string(value)
      nil -> fallback
    end
  end

  @doc """
  The colour of a signed figure as `ZipfelfolioWeb.Format` shows it: green with a plus, red with a
  minus, muted for one that rounds to zero.
  """
  def tone(figure) do
    case sign(figure) do
      :success -> "text-success-ink"
      :error -> "text-error-ink"
      nil -> "text-base-content/70"
    end
  end

  attr :gain, :integer, required: true
  attr :purchase_value, :integer, default: 0, doc: "gives the gain in percent when positive"

  @doc "A gain in euros with its sign and colour, below it in percent of the purchase value."
  def gain(assigns) do
    ~H"""
    <.amount value={@gain} signed tone />
    <div :if={@purchase_value > 0} class={["text-sm", tone(Format.signed_euros(@gain, 2))]}>
      {@gain |> Format.percent_of(@purchase_value) |> Format.signed_percent(1)}
    </div>
    """
  end

  @doc "The `tone` of a signed figure for setzkasten's `stat`: `:success`, `:error` or nil."
  def sign("+" <> _rest), do: :success
  def sign("−" <> _rest), do: :error
  def sign(_unsigned), do: nil

  @doc "A database id from a URL parameter; nil for anything else, beyond SQLite's integers too."
  def parse_id(param) when is_binary(param) do
    case Integer.parse(param) do
      {id, ""} when id in 1..9_223_372_036_854_775_807 -> id
      _invalid -> nil
    end
  end

  def parse_id(_missing), do: nil
end
