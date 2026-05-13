defmodule ManillumWeb.ReferenceLive do
  @moduledoc """
  Four-tab cross-reference index at `/reference`:

    * **People** — cards with `card_type == :person`
    * **Places** — cards with `card_type == :place`
    * **Sources** — cards with `card_type == :source`
    * **Themes** — user-curated tags + their card counts

  Filters into `CatalogLive` when the reviewer clicks an index entry
  (per spec §5 Stream F task 3 — "click an entity to filter Catalog by
  that entity"). The Themes tab is built from `Tag` rows (user-
  curated); the other three are built from `card_type` enum buckets.

  Shipped in Stream F / Slice 11 (M-29).
  """

  use ManillumWeb, :live_view

  alias Manillum.Archive
  alias ManillumWeb.ManillumComponents

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @tabs ~w(people places sources themes)

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Reference")
     |> assign(:card_type_counts, Archive.card_type_counts(actor.id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    actor = socket.assigns.current_user
    tab = if params["tab"] in @tabs, do: params["tab"], else: "people"

    rows = load_rows(actor.id, tab)

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:rows, rows)
     |> assign(:page_title, "Reference · " <> String.capitalize(tab))}
  end

  # ── render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="reference">
      <main class="reference">
        <header class="reference__head">
          <ManillumComponents.kicker>
            ● Manillum · reference
          </ManillumComponents.kicker>
          <h1 class="reference__title">People, places, sources, themes.</h1>
          <p class="reference__lede">
            <em>{tab_count(@tab, @rows)}</em>
            {tab_unit(@tab, length(@rows))} · the cross-reference layer
          </p>
          <nav class="reference__tabs" aria-label="Reference tabs">
            <.link
              :for={tab <- ~w(people places sources themes)}
              patch={~p"/reference?tab=#{tab}"}
              class={[
                "reference__tab",
                tab == @tab && "is-active"
              ]}
            >
              <span class="reference__tab-name">{String.capitalize(tab)}</span>
              <span class="reference__tab-count">{tab_total(tab, @card_type_counts, @rows)}</span>
            </.link>
          </nav>
        </header>

        <div :if={@rows == []} class="reference__empty">
          <p :if={@tab == "themes"}>
            <em>No tags yet.</em> Tags are user-curated cross-references; add them when filing a card.
          </p>
          <p :if={@tab != "themes"}>
            <em>No {@tab} indexed yet.</em>
            File cards of type "{singular(@tab)}" and they'll appear here.
          </p>
        </div>

        <ul :if={@rows != [] and @tab == "themes"} class="reference__list reference__list--themes">
          <li :for={%{tag: tag, count: count} <- @rows}>
            <.link
              patch={~p"/catalog?tag=#{tag.id}"}
              class="reference__row"
            >
              <span class="reference__row-name">#{tag.name}</span>
              <span class="reference__row-count">{count} {pluralize(count, "card", "cards")}</span>
            </.link>
          </li>
        </ul>

        <ul :if={@rows != [] and @tab != "themes"} class="reference__list reference__list--cards">
          <li :for={card <- @rows}>
            <.link navigate={~p"/cards/#{card.id}"} class="reference__row">
              <span class="reference__row-slug">{card.slug}</span>
              <span class="reference__row-front">{card.front}</span>
              <span class="reference__row-call">{card.call_number}</span>
            </.link>
          </li>
        </ul>
      </main>
    </Layouts.app>
    """
  end

  # ── data ────────────────────────────────────────────────────────────

  defp load_rows(user_id, "people"), do: load_typed_cards(user_id, :person)
  defp load_rows(user_id, "places"), do: load_typed_cards(user_id, :place)
  defp load_rows(user_id, "sources"), do: load_typed_cards(user_id, :source)

  defp load_rows(user_id, "themes") do
    Archive.list_tags_with_counts(user_id)
  end

  defp load_typed_cards(user_id, card_type) do
    user_id
    |> Archive.list_filed_cards(card_type: card_type, sort: :call_number, limit: 500)
    |> Enum.sort_by(&String.downcase(&1.slug))
  end

  # ── helpers ─────────────────────────────────────────────────────────

  defp tab_count("themes", rows), do: length(rows)
  defp tab_count(_, rows), do: length(rows)

  defp tab_unit("themes", 1), do: "theme"
  defp tab_unit("themes", _), do: "themes"
  defp tab_unit("people", 1), do: "person"
  defp tab_unit("people", _), do: "people"
  defp tab_unit("places", 1), do: "place"
  defp tab_unit("places", _), do: "places"
  defp tab_unit("sources", 1), do: "source"
  defp tab_unit("sources", _), do: "sources"
  defp tab_unit(_, 1), do: "entry"
  defp tab_unit(_, _), do: "entries"

  defp tab_total("themes", _counts, rows), do: length(rows)
  defp tab_total("people", counts, _rows), do: Map.get(counts, :person, 0)
  defp tab_total("places", counts, _rows), do: Map.get(counts, :place, 0)
  defp tab_total("sources", counts, _rows), do: Map.get(counts, :source, 0)
  defp tab_total(_, _counts, _rows), do: 0

  defp singular("people"), do: "person"
  defp singular("places"), do: "place"
  defp singular("sources"), do: "source"
  defp singular(other), do: other

  defp pluralize(1, sing, _), do: sing
  defp pluralize(_, _, plur), do: plur
end
