defmodule ManillumWeb.DrawersLive do
  @moduledoc """
  Era-based filing cabinet at `/drawers` (index — grid of seven
  drawers, each clickable) and `/drawers/:drawer` (single-drawer
  detail — cards sorted chronologically by `date_token`, with
  `drawer_era/1` providing a fallback midpoint for timeless
  `:LOC` / `:CON` tokens).

  Shipped in Stream F / Slice 11 (M-29).
  """

  use ManillumWeb, :live_view

  import ManillumWeb.CardHelpers

  alias Manillum.Archive
  alias ManillumWeb.ManillumComponents

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    counts = Archive.drawer_counts(actor.id)

    {:ok,
     socket
     |> assign(:drawer_counts, counts)
     |> assign(:total, counts |> Map.values() |> Enum.sum())}
  end

  @impl true
  def handle_params(%{"drawer" => drawer_str}, _uri, socket) do
    actor = socket.assigns.current_user

    case parse_drawer(drawer_str) do
      {:ok, drawer} ->
        cards =
          actor.id
          |> Archive.list_filed_cards(drawer: drawer, limit: 200, sort: :recent)
          |> Enum.sort_by(&date_sort_key/1)

        {:noreply,
         socket
         |> assign(:drawer, drawer)
         |> assign(:drawer_cards, cards)
         |> assign(:live_action, :show)
         |> assign(:page_title, "Drawer · " <> drawer_name(drawer))}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Unknown drawer.")
         |> push_navigate(to: ~p"/drawers")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:drawer, nil)
     |> assign(:drawer_cards, [])
     |> assign(:live_action, :index)
     |> assign(:page_title, "Drawers")}
  end

  # ── render: index ───────────────────────────────────────────────────

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="drawers">
      <main class="drawers">
        <header class="drawers__head">
          <ManillumComponents.kicker>
            ● Manillum · drawers
          </ManillumComponents.kicker>
          <h1 class="drawers__title">Browse the cabinet.</h1>
          <p class="drawers__lede">
            Seven era-shaped drawers · <em>{@total}</em>
            {pluralize(@total, "card", "cards")} filed
          </p>
        </header>

        <ul class="drawers__grid">
          <li :for={drawer <- drawers()}>
            <.link navigate={~p"/drawers/#{drawer}"} class="drawers__cell">
              <header class="drawers__cell-head">
                <span class="drawers__cell-code">{drawer_code(drawer)}</span>
                <span class="drawers__cell-count">
                  {Map.get(@drawer_counts, drawer, 0)} {pluralize(
                    Map.get(@drawer_counts, drawer, 0),
                    "card",
                    "cards"
                  )}
                </span>
              </header>
              <h2 class="drawers__cell-name">{drawer_short(drawer)}</h2>
              <p class="drawers__cell-range">{era_range(drawer)}</p>
              <span class="drawers__cell-bullet" aria-hidden="true"></span>
            </.link>
          </li>
        </ul>
      </main>
    </Layouts.app>
    """
  end

  # ── render: show ────────────────────────────────────────────────────

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active_tab="drawers"
      pin_year={drawer_pin_year(@drawer)}
      pin_label={drawer_short(@drawer)}
    >
      <main class="drawer_show">
        <header class="drawer_show__head">
          <ManillumComponents.kicker>
            ● Manillum · drawer · {drawer_code(@drawer)}
          </ManillumComponents.kicker>
          <h1 class="drawer_show__title">{drawer_short(@drawer)}</h1>
          <p class="drawer_show__lede">
            <em>{length(@drawer_cards)}</em>
            {pluralize(length(@drawer_cards), "card", "cards")} · sorted chronologically · {era_range(
              @drawer
            )}
          </p>
          <nav class="drawer_show__nav" aria-label="Other drawers">
            <.link
              :for={d <- drawers()}
              navigate={~p"/drawers/#{d}"}
              class={[
                "drawer_show__nav-link",
                d == @drawer && "is-active"
              ]}
            >
              {drawer_code(d)}
            </.link>
          </nav>
        </header>

        <div :if={@drawer_cards == []} class="drawer_show__empty">
          <p>
            <em>This drawer is empty.</em> Cards filed under {drawer_short(@drawer)} will land here.
          </p>
        </div>

        <ul :if={@drawer_cards != []} class="drawer_show__list">
          <li :for={card <- @drawer_cards}>
            <.link
              navigate={~p"/cards/#{card.id}"}
              class="drawer_show__row"
              id={"drawer-card-#{card.id}"}
            >
              <span class="drawer_show__row-year">{render_year(card.date_token)}</span>
              <span class="drawer_show__row-front">{card.front}</span>
              <span class="drawer_show__row-call">{card.call_number}</span>
            </.link>
          </li>
        </ul>
      </main>
    </Layouts.app>
    """
  end

  # ── helpers ─────────────────────────────────────────────────────────

  defp parse_drawer(str) when is_binary(str) do
    upcased = str |> String.upcase()
    atom = String.to_existing_atom(upcased)
    if atom in drawers(), do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp drawer_code(:ANT), do: "DR. 01"
  defp drawer_code(:CLA), do: "DR. 02"
  defp drawer_code(:MED), do: "DR. 03"
  defp drawer_code(:REN), do: "DR. 04"
  defp drawer_code(:EAR), do: "DR. 05"
  defp drawer_code(:MOD), do: "DR. 06"
  defp drawer_code(:CON), do: "DR. 07"
  defp drawer_code(other), do: to_string(other)

  defp drawer_short(:ANT), do: "Antiquity"
  defp drawer_short(:CLA), do: "Classical"
  defp drawer_short(:MED), do: "Medieval"
  defp drawer_short(:REN), do: "Renaissance"
  defp drawer_short(:EAR), do: "Early Modern"
  defp drawer_short(:MOD), do: "Modern"
  defp drawer_short(:CON), do: "Contemporary"
  defp drawer_short(other), do: to_string(other)

  defp era_range(drawer) do
    {from, to} = drawer_era(drawer)
    format_year(from) <> " — " <> format_year(to)
  end

  defp format_year(y) when y < 0, do: "#{-y} BC"
  defp format_year(y), do: "#{y}"

  defp drawer_pin_year(drawer) do
    {from, to} = drawer_era(drawer)
    div(from + to, 2)
  end

  defp render_year(token) do
    case parse_date_token_year(token) do
      nil -> token
      y when y < 0 -> "#{-y} BC"
      y -> "#{y}"
    end
  end

  defp pluralize(1, sing, _), do: sing
  defp pluralize(_, _, plur), do: plur
end
