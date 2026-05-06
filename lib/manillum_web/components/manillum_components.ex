defmodule ManillumWeb.ManillumComponents do
  @moduledoc """
  Manillum's distinctive UI components.

  Each component pairs a `~H` template with a hand-written CSS class in
  `assets/css/components/<name>.css`. Markup carries one canonical class;
  the CSS owns the visual treatment. See `/docs/design-system.md` for the
  discipline rules (tokens vs components vs Tailwind utilities).

  Components in this module:

    * `topbar/1` — wordmark + nav + meta
    * `era_band/1` — persistent timeline chrome
    * `card/1` — recto/verso index card (the signature surface)
    * `call_number/1` — boxed mono identifier
    * `drawer_label/1` — colour-bullet drawer name
    * `stamp/1` — square mono badge tilted ~8°
    * `gutter_action/1` — marginal FILE affordance
    * `drop_cap/1` — oxblood Spectral initial
    * `meta_label/1` — small mono kicker / metadata strip
    * `kicker/1` — display-tracking on-this-day style kicker
    * `qry_stamp/1` — QRY № provenance ribbon
    * `caption/1` — italic Newsreader caption
    * `tag/1` — cross-reference tag
    * `btn/1` — Manillum-style button (italic, no radius)
    * `action_pill/1` — tiny inline action
    * `toast/1` — flash / notification (NOT DaisyUI's toast)
    * `filing_tray/1` — right-side drawer
    * `convo_header/1` — kicker + display title + opened stamp
    * `message/1` — speaker gutter + body for a chat turn
    * `composing_indicator/1` — three-dot streaming pulse
    * `composer/1` — "Ask Livy —" bottom input bar

  Components in this module deliberately don't rely on DaisyUI classes —
  they're the visual signature of the app. DaisyUI lives in
  `core_components.ex` and `ash_authentication_phoenix` UI for forms,
  modals, dropdowns, and any AshAuth-rendered surface.
  """

  use Phoenix.Component

  # `<.icon>` is the heroicons helper from CoreComponents; we use it for
  # inline action glyphs so they pick up `currentColor` and align via
  # vertical-align: middle instead of relying on text-glyph metrics.
  import ManillumWeb.CoreComponents, only: [icon: 1]

  # ── era boundaries — single source of truth, mirrored from the design
  @eras [
    {"Antiquity", -3000, -500},
    {"Classical", -500, 500},
    {"Middle Ages", 500, 1400},
    {"Renaissance", 1400, 1650},
    {"Early Modern", 1650, 1800},
    {"Long 19th c.", 1800, 1914},
    {"Short 20th c.", 1914, 1991},
    {"Now", 1991, 2026}
  ]

  @doc "Returns the list of Manillum era tuples — `{label, from_year, to_year}`."
  def eras, do: @eras

  @doc """
  Maps a year onto the 0..1 timeline range using **even-era spacing**:
  each of the 8 eras claims an equal slice of the band, and the year's
  position within its era interpolates linearly inside that slice.

  This trades historical-time-accuracy for readability — the user
  navigates by era, not by linear millennia. Antiquity (which spans 2,500
  years) and "Now" (which spans 35) get the same band width, so all era
  labels remain legible at any viewport width.
  """
  def era_x(year) do
    {idx, from, to} = locate_era(year)
    era_width = 1.0 / length(@eras)
    fraction = if to == from, do: 0.0, else: (year - from) / (to - from)
    fraction = max(0.0, min(1.0, fraction))
    idx * era_width + fraction * era_width
  end

  # Returns {era_index, era_from, era_to} for a given year, clamping to
  # the first/last era when the year falls outside the defined range.
  defp locate_era(year) do
    case Enum.find_index(@eras, fn {_, from, to} -> year >= from and year < to end) do
      nil when year < -3000 ->
        {_, from, to} = hd(@eras)
        {0, from, to}

      nil ->
        {_, from, to} = List.last(@eras)
        {length(@eras) - 1, from, to}

      idx ->
        {_, from, to} = Enum.at(@eras, idx)
        {idx, from, to}
    end
  end

  defp pct(n) when is_number(n), do: "#{Float.round(n * 100, 4)}%"

  # ── format a year as "1200 BC" / "1519 AD" / "Now"
  defp format_year(nil), do: ""
  defp format_year(y) when y < 0, do: "#{-y} BC"
  defp format_year(y), do: "#{y}"

  # ────────────────────────────────────────────────────────────────────
  # topbar — Manillum wordmark, nav tabs, and right-side meta line
  # ────────────────────────────────────────────────────────────────────
  attr :active, :string, default: nil, doc: "tab key matching one of the slots"
  attr :tagline, :string, default: "— a personal history, with Livy."
  attr :meta, :string, default: nil

  slot :tab, doc: "navigation tab" do
    attr :id, :string, required: true
    attr :href, :string, required: true
  end

  def topbar(assigns) do
    ~H"""
    <div class="topbar">
      <div class="topbar__brand">
        <a href="/" class="topbar__wordmark">Manillum</a>
        <span :if={@tagline} class="topbar__tagline">{@tagline}</span>
      </div>
      <nav :if={@tab != []} class="topbar__nav">
        <a
          :for={t <- @tab}
          href={t.href}
          aria-current={if t.id == @active, do: "page"}
        >
          {render_slot(t)}
        </a>
      </nav>
      <div :if={@meta} class="topbar__meta">{@meta}</div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # era_band — the timeline chrome strip rendered at the top of every page
  # ────────────────────────────────────────────────────────────────────
  attr :pin_year, :integer, default: nil, doc: "year the user is anchored to"
  attr :pin_label, :string, default: nil, doc: "label below the pin"
  attr :dim, :boolean, default: false

  attr :events, :list,
    default: [],
    doc: """
    Mention events to mark on the band. Each event is a map with at least
    `:year` (required); `:title`, `:summary`, `:month`, `:day`, `:id`,
    and `:message_id` are surfaced when present. Marks render at
    `era_x(year)` with a hover tooltip showing the formatted date + title.
    """

  def era_band(assigns) do
    pin_x = if assigns.pin_year, do: era_x(assigns.pin_year), else: nil

    pin_anchor =
      cond do
        is_nil(pin_x) -> nil
        pin_x < 0.10 -> :left
        pin_x > 0.85 -> :right
        true -> :center
      end

    assigns = assign(assigns, pin_x: pin_x, pin_anchor: pin_anchor)

    ~H"""
    <div class={["era_band", @dim && "era_band--dim"]}>
      <div class="era_band__head">
        <span>—3000 bc</span>
        <em>The timeline</em>
        <span>{Date.utc_today().year}</span>
      </div>
      <div class="era_band__track">
        <div class="era_band__rule"></div>
        <% era_w = 1.0 / length(eras()) %>
        <%= for {{label, _from, _to}, i} <- Enum.with_index(eras()) do %>
          <% x1 = i * era_w
          tone = if rem(i, 2) == 0, do: "era_band__era--even", else: "era_band__era--odd" %>
          <div
            class={["era_band__era", tone]}
            style={"--era-x1:#{pct(x1)};--era-x2:#{pct(era_w)}"}
          >
          </div>
          <div :if={i > 0} class="era_band__tick" style={"--era-x1:#{pct(x1)}"}></div>
          <div class="era_band__label" style={"--era-cx:#{pct(x1 + era_w / 2)}"}>
            {label}
          </div>
        <% end %>
        <%= for event <- @events do %>
          <% x = event_x(event)
          tooltip_anchor = tooltip_anchor_for(x) %>
          <a
            :if={x}
            class="era_band__event"
            style={"--event-x:#{pct(x)}"}
            href={event_href(event)}
            data-mention-id={Map.get(event, :id)}
          >
            <span class={["era_band__event-tooltip", "era_band__event-tooltip--#{tooltip_anchor}"]}>
              <span class="era_band__event-head">
                <span class="era_band__event-year">{event_year_magnitude(event)}</span>
                <span class="era_band__event-meta">
                  {event_period(event)} · {String.upcase(event_era_label(event))}
                </span>
              </span>
              <span :if={Map.get(event, :title)} class="era_band__event-title">
                {Map.get(event, :title)}
              </span>
              <span :if={event_subdate(event)} class="era_band__event-subtitle">
                {event_subdate(event)}
              </span>
              <span :if={Map.get(event, :summary)} class="era_band__event-rule"></span>
              <span :if={Map.get(event, :summary)} class="era_band__event-body">
                {Map.get(event, :summary)}
              </span>
            </span>
          </a>
        <% end %>
        <div :if={@pin_year} class="era_band__pin" style={"--pin-x:#{pct(@pin_x)}"}>
          <div class={["era_band__pin-label", "era_band__pin-label--#{@pin_anchor}"]}>
            {format_year(@pin_year)}<span :if={@pin_label}> · {@pin_label}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Compute the band x-position for an event, returning nil if it lacks a
  # year (defensive — the LiveView is supposed to filter these, but the
  # component shouldn't crash on a malformed payload).
  defp event_x(%{year: year}) when is_integer(year), do: era_x(year)
  defp event_x(_), do: nil

  # Anchor the tooltip to a band edge when the mark sits near it, so the
  # popover doesn't overflow horizontally.
  defp tooltip_anchor_for(nil), do: :center
  defp tooltip_anchor_for(x) when x < 0.12, do: :left
  defp tooltip_anchor_for(x) when x > 0.88, do: :right
  defp tooltip_anchor_for(_), do: :center

  defp event_href(%{message_id: id}) when is_binary(id), do: "#message-#{id}"
  defp event_href(_), do: nil

  defp event_year_magnitude(%{year: year}) when is_integer(year), do: abs(year)
  defp event_year_magnitude(_), do: ""

  defp event_period(%{year: year}) when is_integer(year) and year < 0, do: "BC"
  defp event_period(_), do: "AD"

  defp event_era_label(%{year: year}) when is_integer(year) do
    {idx, _, _} = locate_era(year)

    case Enum.at(eras(), idx) do
      {label, _, _} -> label
      _ -> ""
    end
  end

  defp event_era_label(_), do: ""

  # The event subtitle renders the day/month part of the date (the year
  # already lives in the big year header). Returns nil when month is
  # absent — a year-only mention has no subdate to show.
  defp event_subdate(%{month: m, day: d}) when is_integer(m) and is_integer(d),
    do: "#{d} #{month_name(m)}"

  defp event_subdate(%{month: m}) when is_integer(m), do: month_name(m)
  defp event_subdate(_), do: nil

  @doc """
  Format an event's date with the precision Livy supplied. Examples:

      iex> format_event_date(%{year: 1066})
      "1066"

      iex> format_event_date(%{year: 1066, month: 10})
      "October 1066"

      iex> format_event_date(%{year: 1066, month: 10, day: 14})
      "14 October 1066"

      iex> format_event_date(%{year: -44, month: 3, day: 15})
      "15 March 44 BC"

      iex> format_event_date(%{year: -753})
      "753 BC"
  """
  @spec format_event_date(map()) :: String.t()
  def format_event_date(%{year: year} = event) do
    month = Map.get(event, :month)
    day = Map.get(event, :day)
    format_event_date(year, month, day)
  end

  @spec format_event_date(integer(), integer() | nil, integer() | nil) :: String.t()
  def format_event_date(year, month, day) when is_integer(year) do
    case {month, day} do
      {nil, _} -> format_year(year)
      {m, nil} -> "#{month_name(m)} #{format_year(year)}"
      {m, d} -> "#{d} #{month_name(m)} #{format_year(year)}"
    end
  end

  @month_names %{
    1 => "January",
    2 => "February",
    3 => "March",
    4 => "April",
    5 => "May",
    6 => "June",
    7 => "July",
    8 => "August",
    9 => "September",
    10 => "October",
    11 => "November",
    12 => "December"
  }

  defp month_name(m) when m in 1..12, do: Map.fetch!(@month_names, m)

  # ────────────────────────────────────────────────────────────────────
  # card — recto/verso index card. The signature surface.
  # ────────────────────────────────────────────────────────────────────
  attr :face, :atom, values: [:recto, :verso, :draft, :preview, :list], default: :recto
  attr :tint, :string, default: nil, doc: "drawer tint colour, e.g. var(--color-forest)"
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div
      class={["card", "card--#{@face}", @class]}
      style={@tint && "--card-tint:#{@tint}"}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def card_head(assigns) do
    ~H"""
    <div class={["card__head", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def card_question(assigns) do
    ~H"""
    <div class={["card__question", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def card_answer(assigns) do
    ~H"""
    <div class={["card__answer", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def card_foot(assigns) do
    ~H"""
    <div class={["card__foot", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # call_number — boxed mono identifier (the library-card slug)
  # ────────────────────────────────────────────────────────────────────
  attr :tone, :atom, values: [:oxblood, :forest, :brass], default: :oxblood
  attr :inline, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def call_number(assigns) do
    ~H"""
    <span
      class={[
        "call_number",
        @tone == :forest && "call_number--forest",
        @tone == :brass && "call_number--brass",
        @inline && "call_number--inline"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # drawer_label — colour-bulleted drawer name
  # ────────────────────────────────────────────────────────────────────
  attr :tint, :string, default: nil, doc: "css colour for the bullet"
  attr :variant, :atom, values: [:default, :strong, :display], default: :default
  slot :inner_block, required: true

  def drawer_label(assigns) do
    ~H"""
    <span
      class={[
        "drawer_label",
        @variant == :strong && "drawer_label--strong",
        @variant == :display && "drawer_label--display"
      ]}
      style={@tint && "--drawer-tint:#{@tint}"}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # stamp — square mono badge, ~8° tilt
  # ────────────────────────────────────────────────────────────────────
  attr :variant, :atom, values: [:default, :upright, :small, :filled, :ribbon], default: :default
  slot :inner_block, required: true

  def stamp(assigns) do
    ~H"""
    <div class={[
      "stamp",
      @variant == :upright && "stamp--upright",
      @variant == :small && "stamp--small",
      @variant == :filled && "stamp--filled",
      @variant == :ribbon && "stamp--ribbon"
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # gutter_action — left-margin paragraph affordance
  # ────────────────────────────────────────────────────────────────────
  attr :index, :string, required: true, doc: "paragraph index, e.g. ¶ 2"
  attr :active, :boolean, default: false
  attr :show_action, :boolean, default: true
  attr :body_class, :string, default: nil
  slot :action, doc: "the file affordance content (defaults to a plus icon + FILE)"
  slot :inner_block, required: true

  def gutter_row(assigns) do
    ~H"""
    <div class="gutter__row">
      <div class="gutter">
        <div class="gutter__index">{@index}</div>
        <button
          :if={@show_action}
          class={["gutter_action", @active && "is-active"]}
          type="button"
        >
          <%= if @action != [] do %>
            {render_slot(@action)}
          <% else %>
            <.icon name="hero-plus-micro" /> FILE
          <% end %>
        </button>
      </div>
      <div class={["gutter__body", @active && "is-active", @body_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # drop_cap — oxblood Spectral initial that floats on a paragraph
  # ────────────────────────────────────────────────────────────────────
  attr :size, :atom, values: [:default, :sm, :lg, :xl], default: :default
  slot :inner_block, required: true

  def drop_cap(assigns) do
    ~H"""
    <span class={[
      "drop_cap",
      @size == :sm && "drop_cap--sm",
      @size == :lg && "drop_cap--lg",
      @size == :xl && "drop_cap--xl"
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # meta_label — small mono kicker / metadata strip
  # ────────────────────────────────────────────────────────────────────
  attr :tone, :atom, values: [:faint, :oxblood, :forest, :brass, :ink], default: :faint
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def meta_label(assigns) do
    ~H"""
    <span class={[
      "meta_label",
      @tone == :oxblood && "meta_label--oxblood",
      @tone == :forest && "meta_label--forest",
      @tone == :brass && "meta_label--brass",
      @tone == :ink && "meta_label--ink",
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def kicker(assigns) do
    ~H"""
    <span class={["kicker", @class]}>{render_slot(@inner_block)}</span>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def caption(assigns) do
    ~H"""
    <div class={["caption", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # qry_stamp — QRY № provenance ribbon
  # ────────────────────────────────────────────────────────────────────
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def qry_stamp(assigns) do
    ~H"""
    <span class={["qry_stamp", @class]}>{render_slot(@inner_block)}</span>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # tag — cross-reference tag (with optional × remove and "+ tag" affordance)
  # ────────────────────────────────────────────────────────────────────
  attr :tint, :string, default: nil, doc: "css colour for border + text"
  attr :variant, :atom, values: [:default, :remove, :add, :small], default: :default
  attr :rest, :global
  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span
      class={[
        "tag",
        @variant == :remove && "tag tag--remove",
        @variant == :add && "tag tag--add",
        @variant == :small && "tag tag--small"
      ]}
      style={@tint && "--tag-tint:#{@tint}"}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # btn — Manillum-style button (italic Newsreader, no radius)
  # ────────────────────────────────────────────────────────────────────
  attr :variant, :atom, values: [:primary, :ghost, :bare], default: :primary
  attr :size, :atom, values: [:default, :sm], default: :default
  attr :type, :string, default: "button"
  attr :rest, :global, include: ~w(href phx-click phx-disable-with disabled)
  slot :inner_block, required: true

  def btn(assigns) do
    ~H"""
    <%= if Map.has_key?(@rest, :href) do %>
      <a
        class={[
          "btn-manillum",
          @variant == :ghost && "btn-manillum--ghost",
          @variant == :bare && "btn-manillum--bare",
          @size == :sm && "btn-manillum--sm"
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </a>
    <% else %>
      <button
        type={@type}
        class={[
          "btn-manillum",
          @variant == :ghost && "btn-manillum--ghost",
          @variant == :bare && "btn-manillum--bare",
          @size == :sm && "btn-manillum--sm"
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  attr :variant, :atom, values: [:primary, :ghost, :bare], default: :primary
  attr :rest, :global
  slot :inner_block, required: true

  def action_pill(assigns) do
    ~H"""
    <span
      class={[
        "action_pill",
        @variant == :ghost && "action_pill--ghost",
        @variant == :bare && "action_pill--bare"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # toast — Manillum's flash / notification (NOT DaisyUI's toast)
  # ────────────────────────────────────────────────────────────────────
  attr :id, :string, default: nil
  attr :kind, :atom, values: [:info, :ok, :warn, :error], default: :info
  attr :title, :string, default: nil
  attr :kicker, :string, default: nil
  attr :rest, :global
  slot :inner_block

  def toast(assigns) do
    ~H"""
    <div id={@id} class={["toast", "toast--#{@kind}"]} role="status" {@rest}>
      <div :if={@kicker} class="toast__kicker">{@kicker}</div>
      <div :if={@title} class="toast__title">{@title}</div>
      <div :if={@inner_block != []} class="toast__body">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # filing_tray — slide-in drawer for cataloging drafts
  # ────────────────────────────────────────────────────────────────────
  attr :state, :atom, values: [:draft, :review], default: :draft
  attr :title, :string, default: nil
  attr :kicker, :string, default: nil
  attr :sub, :string, default: nil
  slot :actions, doc: "buttons rendered next to the title"
  slot :inner_block, required: true

  def filing_tray(assigns) do
    ~H"""
    <aside class={["filing_tray", "filing_tray--#{@state}"]}>
      <header class="filing_tray__head">
        <div class="filing_tray__kicker">
          <span>{@kicker || "FILING TRAY"}</span>
          <button class="filing_tray__close" type="button" aria-label="Close filing tray">
            <.icon name="hero-x-mark-mini" /> close
          </button>
        </div>
        <div :if={@title} class="filing_tray__title">{@title}</div>
        <div :if={@sub} class="filing_tray__sub">{@sub}</div>
        <div :if={@actions != []} class="filing_tray__actions">
          {render_slot(@actions)}
        </div>
      </header>
      <div class="filing_tray__body">{render_slot(@inner_block)}</div>
    </aside>
    """
  end

  attr :prov, :string, default: nil

  def draft_skeleton(assigns) do
    ~H"""
    <div class="card card--draft">
      <div :if={@prov} class="meta_label" style="display:block;text-align:right;margin-bottom:.5rem">
        {@prov}
      </div>
      <div class="skeleton_bar" style="width:6.875rem;margin-bottom:.5rem"></div>
      <div class="skeleton_bar skeleton_bar--80"></div>
      <div class="skeleton_bar skeleton_bar--95"></div>
      <div class="skeleton_bar skeleton_bar--60"></div>
      <div class="cataloging_indicator">cataloging…</div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # page — linen-grounded surface; useful as a top-level wrapper
  # ────────────────────────────────────────────────────────────────────
  attr :class, :string, default: nil
  attr :dim, :boolean, default: false
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div class={["page", @dim && "page--dim", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # convo_header — left: ● Conversation № 89 · N exchanges + display title;
  # right: opened-at stamp. Sits below the era band, above the thread.
  # ────────────────────────────────────────────────────────────────────
  attr :query_number, :integer, required: true
  attr :title, :string, default: nil, doc: "conversation title or nil for untitled"
  attr :exchanges, :integer, default: nil
  attr :opened_at, :any, default: nil, doc: "DateTime / NaiveDateTime / time string"

  def convo_header(assigns) do
    ~H"""
    <header class="convo_header">
      <div>
        <span class="qry_stamp">
          Conversation № {@query_number}<span :if={@exchanges && @exchanges > 0}>
            · {@exchanges} {pluralize(@exchanges, "exchange", "exchanges")}</span>
        </span>
        <h1 class="convo_header__title">
          {@title || "Untitled conversation"}
        </h1>
      </div>
      <div :if={@opened_at} class="convo_header__opened">
        Opened {format_clock(@opened_at)}
      </div>
    </header>
    """
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_, _singular, plural), do: plural

  # ────────────────────────────────────────────────────────────────────
  # message — single chat turn. Speaker label on the left, body on the
  # right. Body styling diverges by role (user italic on brass rule;
  # assistant ink on rule). Inner block is the rendered content.
  # ────────────────────────────────────────────────────────────────────
  attr :id, :string, default: nil
  attr :role, :atom, values: [:user, :assistant], required: true
  attr :timestamp, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def message(assigns) do
    ~H"""
    <article id={@id} class={["message", "message--#{@role}", @class]} {@rest}>
      <div class="message__speaker">
        {speaker_for(@role)}<br :if={@timestamp} />{@timestamp}
      </div>
      <div class="message__body">
        {render_slot(@inner_block)}
      </div>
    </article>
    """
  end

  defp speaker_for(:user), do: "You"
  defp speaker_for(:assistant), do: "Livy"

  # ────────────────────────────────────────────────────────────────────
  # composing_indicator — three pulsing oxblood dots + italic caption.
  # Shown while the assistant is streaming a response.
  # ────────────────────────────────────────────────────────────────────
  attr :label, :string, default: "Livy is composing…"

  def composing_indicator(assigns) do
    ~H"""
    <div class="composing" aria-live="polite">
      <span class="composing__dots" aria-hidden="true">
        <i></i><i></i><i></i>
      </span>
      <span>{@label}</span>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # composer — "Ask Livy —" bottom input bar. Wraps a Phoenix form with a
  # mono brass kicker on the left and a `↵ ASK` submit on the right.
  # ────────────────────────────────────────────────────────────────────
  attr :form, :any, required: true, doc: "Phoenix.HTML.Form built via AshPhoenix.Form"
  attr :field, :atom, default: :content, doc: "form field for the message body"
  attr :placeholder, :string, default: "Ask Livy anything about history…"
  attr :phx_change, :string, default: nil
  attr :phx_submit, :string, default: "send_message"
  attr :disabled, :boolean, default: false

  def composer(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@form}
      phx-change={@phx_change}
      phx-submit={@phx_submit}
      class="composer"
    >
      <span class="composer__kicker">Ask Livy —</span>
      <input
        type="text"
        name={f[@field].name}
        value={f[@field].value}
        placeholder={@placeholder}
        autocomplete="off"
        phx-mounted={Phoenix.LiveView.JS.focus()}
        class="composer__input"
      />
      <button type="submit" class="composer__submit" disabled={@disabled}>
        ↵ Ask
      </button>
    </.form>
    """
  end

  # Format a datetime as 24h HH:MM in UTC. Conversation timestamps are
  # naive UTC; rendering them in the user's local zone is a follow-up.
  defp format_clock(%DateTime{} = dt) do
    "#{pad2(dt.hour)}:#{pad2(dt.minute)}"
  end

  defp format_clock(%NaiveDateTime{} = dt) do
    "#{pad2(dt.hour)}:#{pad2(dt.minute)}"
  end

  defp format_clock(s) when is_binary(s), do: s
  defp format_clock(_), do: ""

  defp pad2(n) when is_integer(n) and n < 10, do: "0#{n}"
  defp pad2(n) when is_integer(n), do: "#{n}"
end
