defmodule ZipfelfolioWeb.CoreComponents do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :class, :any, default: nil
  attr :as, :string, default: "section"
  attr :level, :integer, default: 2
  attr :rest, :global
  slot :inner_block

  def card(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@as} class={["card", "mb-3", @class]} {@rest}>
      <div class="card-body">
        <%= if present?(@title) do %>
          <.dynamic_tag tag_name={"h#{@level}"} class="card-title">{@title}</.dynamic_tag>
          <p :if={present?(@subtitle)} class="card-subtitle">{@subtitle}</p>
        <% end %>
        {render_slot(@inner_block)}
      </div>
    </.dynamic_tag>
    """
  end

  attr :id, :string, doc: "the optional id of the flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"
  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "alert alert-dismissible d-flex align-items-start gap-2 mb-3",
        @kind == :info && "alert-success",
        @kind == :error && "alert-danger"
      ]}
      {@rest}
    >
      <div>
        <strong :if={@title} class="d-block">{@title}</strong>
        {msg}
      </div>
      <button type="button" class="btn-close" aria-label="Schließen"></button>
    </div>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="Keine Verbindung"
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        Verbindung wird wiederhergestellt …
      </.flash>
      <.flash
        id="server-error"
        kind={:error}
        title="Etwas ist schiefgelaufen"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Verbindung wird wiederhergestellt …
      </.flash>
    </div>
    """
  end

  attr :variant, :string, default: "primary", doc: "the felt-css button variant (btn-<variant>)"
  attr :size, :string, default: nil, values: [nil, "sm", "lg"]
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :classes, [
        "btn",
        "btn-#{assigns.variant}",
        assigns.size && "btn-#{assigns.size}",
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :switch, :boolean, default: false, doc: "a checkbox drawn as a switch"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "extra classes for the control"
  attr :wrapper_class, :any, default: "mb-3"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={["form-check", @switch && "form-switch", @wrapper_class]}>
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        role={@switch && "switch"}
        class={["form-check-input", @errors != [] && "is-invalid", @class]}
        {@rest}
      />
      <label :if={@label} class="form-check-label" for={@id}>{@label}</label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        class={["form-select", @errors != [] && "is-invalid", @class]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <textarea
        id={@id}
        name={@name}
        class={["form-control", @errors != [] && "is-invalid", @class]}
        {@rest}
      >{Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="form-label" for={@id}>{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          if(@type in ~w(range), do: "form-range", else: "form-control"),
          @type == "color" && "form-control-color",
          @errors != [] && "is-invalid",
          @class
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <div class="invalid-feedback d-block">{render_slot(@inner_block)}</div>
    """
  end

  attr :class, :any, default: nil
  attr :title_class, :any, default: nil
  slot :inner_block, required: true
  slot :leading
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={["d-flex align-items-center gap-2 mb-3", @class]}>
      {render_slot(@leading)}
      <div class="me-auto">
        <h1 class={["h2 mb-0", @title_class]}>{render_slot(@inner_block)}</h1>
        <p :if={@subtitle != []} class="small text-body-secondary mb-0">{render_slot(@subtitle)}</p>
      </div>
      {render_slot(@actions)}
    </header>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :value_class, :any, default: nil
  attr :class, :any, default: nil

  slot :prefix, doc: "a quiet remark before the value, such as „brutto“"

  slot :note do
    attr :class, :any
  end

  @doc "A key figure in a card: its label, its value and notes below."
  def stat(assigns) do
    ~H"""
    <div class={["card h-100", @class]} id={@id}>
      <div class="card-body">
        <div class="stat">
          <span class="stat-label">{@label}</span>
          <span class={["stat-value", @value_class]}>
            <span :if={@prefix != []} class="small fw-normal text-body-secondary">
              {render_slot(@prefix)}
            </span>
            {@value}
          </span>
          <span :for={note <- @note} class={["small", note[:class]]}>{render_slot(note)}</span>
        </div>
      </div>
    </div>
    """
  end

  @doc "The class that mutes an amount of zero in a column of amounts."
  def muted(0), do: "text-body-tertiary"
  def muted(_amount), do: nil

  # The click dummy's line icons on a 24 px grid, each as the paths it draws.
  @icons %{
    "back" => ["m15 6-6 6 6 6"],
    "chevron" => ["m9 6 6 6-6 6"],
    "coins" => [
      "M3 7a6 3 0 1 0 12 0 6 3 0 1 0-12 0",
      "M3 7v4c0 1.7 2.7 3 6 3s6-1.3 6-3V7M3 11v4c0 1.7 2.7 3 6 3 1 0 2-.1 2.8-.4",
      "M13 15a4 2 0 1 0 8 0 4 2 0 1 0-8 0",
      "M13 15v3c0 1.1 1.8 2 4 2s4-.9 4-2v-3"
    ],
    "down" => ["m6 9 6 6 6-6"],
    "gear" => [
      "M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
      "M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"
    ],
    "home" => ["M3 11 12 4l9 7M5 10v10h14V10M10 20v-6h4v6"],
    "key" => ["M12 15a4 4 0 1 1-8 0 4 4 0 0 1 8 0", "m11 12 9-9M16 7l3 3M14 9l2 2"],
    "layers" => ["m12 3 9 5-9 5-9-5zM3 13l9 5 9-5M3 17.5l9 5 9-5"],
    "logout" => ["M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"],
    "sidebar" => [
      "M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z",
      "M9 4v16M16 9l-3 3 3 3"
    ],
    "wallet" => ["M3 7h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM3 7l13-4v4M17 13.5h.01"]
  }

  attr :name, :string, required: true, values: Map.keys(@icons)
  attr :class, :any, default: nil

  @doc "A line icon in the current text colour, hidden from screen readers."
  def icon(assigns) do
    assigns = assign(assigns, :paths, Map.fetch!(@icons, assigns.name))

    ~H"""
    <svg class={["app-icon", @class]} viewBox="0 0 24 24" aria-hidden="true">
      <path :for={d <- @paths} d={d} />
    </svg>
    """
  end

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
  def tone("+" <> _rest), do: "text-success"
  def tone("−" <> _rest), do: "text-danger"
  def tone(_unsigned), do: "text-body-secondary"

  @doc "A database id from a URL parameter; nil for anything else, beyond SQLite's integers too."
  def parse_id(param) when is_binary(param) do
    case Integer.parse(param) do
      {id, ""} when id in 1..9_223_372_036_854_775_807 -> id
      _invalid -> nil
    end
  end

  def parse_id(_missing), do: nil

  def show(js \\ %JS{}, selector) do
    JS.show(js, to: selector, time: 200, transition: {"fade", "opacity-0", "opacity-100"})
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js, to: selector, time: 200, transition: {"fade", "opacity-100", "opacity-0"})
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
