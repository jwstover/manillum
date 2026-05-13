defmodule ManillumWeb.CatalogLive do
  @moduledoc """
  Search-first browse view at `/catalog`. Free-text search across the
  user's filed cards (slug / front / back), filterable by drawer,
  card_type, and tag. Result rows render call number, drawer, and the
  recto question; clicking a row opens `/cards/:id`.

  Shipped in Stream F / Slice 11 (M-29). Real-time updates via the
  `"user:\#{user_id}:archive"` PubSub topic (filed cards stream in,
  see spec §7.3) are deferred to the live-streaming polish pass —
  this ships as a paged read-only list driven by
  `Archive.list_filed_cards/2`.
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
    tags = Archive.list_tags_with_counts(actor.id)
    total = counts |> Map.values() |> Enum.sum()

    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:drawer_counts, counts)
     |> assign(:tags, tags)
     |> assign(:total, total)
     |> assign(:filters, %{
       query: "",
       drawer: nil,
       card_type: nil,
       tag_id: nil
     })
     |> assign_cards()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      query: params["q"] || "",
      drawer: atomize_filter(params["drawer"], drawers()),
      card_type:
        atomize_filter(params["type"], ~w(person event place concept source date artifact)a),
      tag_id: params["tag"]
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign_cards()}
  end

  @impl true
  def handle_event("search", %{"q" => q} = params, socket) do
    {:noreply,
     push_patch(socket,
       to: catalog_path(socket.assigns.filters, %{query: q, tag_id: params["tag"]})
     )}
  end

  def handle_event("filter_drawer", %{"drawer" => drawer}, socket) do
    drawer = if drawer == "", do: nil, else: drawer
    {:noreply, push_patch(socket, to: catalog_path(socket.assigns.filters, %{drawer: drawer}))}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    type = if type == "", do: nil, else: type
    {:noreply, push_patch(socket, to: catalog_path(socket.assigns.filters, %{card_type: type}))}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/catalog")}
  end

  # ── render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="catalog">
      <main class="catalog">
        <header class="catalog__head">
          <ManillumComponents.kicker>
            ● Manillum · catalog
          </ManillumComponents.kicker>
          <h1 class="catalog__title">Search the catalog.</h1>
          <p class="catalog__lede">
            <em>{@total}</em>
            {pluralize(@total, "card", "cards")} on file
            <span :if={any_filter?(@filters)} class="catalog__lede-filter">
              · {format_filters(@filters, @tags)}
            </span>
          </p>
        </header>

        <.form
          for={%{}}
          as={:search}
          phx-change="search"
          phx-submit="search"
          class="catalog__search"
        >
          <span class="catalog__search-kicker">QUERY ▸</span>
          <input
            type="text"
            name="q"
            value={@filters.query}
            placeholder="search slugs, fronts, backs…"
            autocomplete="off"
            class="catalog__search-input"
            phx-debounce="200"
          />
          <input :if={@filters.tag_id} type="hidden" name="tag" value={@filters.tag_id} />
          <button
            :if={any_filter?(@filters)}
            type="button"
            class="catalog__search-clear"
            phx-click="clear"
          >
            clear ✕
          </button>
        </.form>

        <div class="catalog__body">
          <aside class="catalog__filters" aria-label="Filters">
            <div class="catalog__filter-block">
              <h2 class="catalog__filter-head">By drawer</h2>
              <ul class="catalog__filter-list">
                <li>
                  <button
                    type="button"
                    class={[
                      "catalog__filter-item",
                      is_nil(@filters.drawer) && "is-active"
                    ]}
                    phx-click="filter_drawer"
                    phx-value-drawer=""
                  >
                    <span>All drawers</span><span class="catalog__filter-count">{@total}</span>
                  </button>
                </li>
                <li :for={d <- drawers()}>
                  <button
                    type="button"
                    class={[
                      "catalog__filter-item",
                      @filters.drawer == d && "is-active"
                    ]}
                    phx-click="filter_drawer"
                    phx-value-drawer={to_string(d)}
                  >
                    <span>{drawer_name(d)}</span>
                    <span class="catalog__filter-count">{Map.get(@drawer_counts, d, 0)}</span>
                  </button>
                </li>
              </ul>
            </div>

            <div class="catalog__filter-block">
              <h2 class="catalog__filter-head">By card type</h2>
              <ul class="catalog__filter-list">
                <li>
                  <button
                    type="button"
                    class={[
                      "catalog__filter-item",
                      is_nil(@filters.card_type) && "is-active"
                    ]}
                    phx-click="filter_type"
                    phx-value-type=""
                  >
                    <span>Any type</span>
                  </button>
                </li>
                <li :for={t <- ~w(person event place concept source date artifact)a}>
                  <button
                    type="button"
                    class={[
                      "catalog__filter-item",
                      @filters.card_type == t && "is-active"
                    ]}
                    phx-click="filter_type"
                    phx-value-type={to_string(t)}
                  >
                    <span>{t}</span>
                  </button>
                </li>
              </ul>
            </div>

            <div :if={@tags != []} class="catalog__filter-block">
              <h2 class="catalog__filter-head">By tag</h2>
              <ul class="catalog__filter-list">
                <li :for={%{tag: tag, count: count} <- Enum.take(@tags, 12)}>
                  <.link
                    patch={catalog_path(@filters, %{tag_id: tag.id})}
                    class={[
                      "catalog__filter-item",
                      @filters.tag_id == tag.id && "is-active"
                    ]}
                  >
                    <span>· {tag.name}</span>
                    <span class="catalog__filter-count">{count}</span>
                  </.link>
                </li>
              </ul>
            </div>
          </aside>

          <section class="catalog__results">
            <div :if={@cards == []} class="catalog__empty">
              <p :if={any_filter?(@filters)}>
                No filed cards match these filters.
                <button type="button" class="catalog__empty-clear" phx-click="clear">
                  clear filters
                </button>
              </p>
              <p :if={!any_filter?(@filters)}>
                <em>Nothing's been filed yet.</em>
                Save a fact from a conversation, or
                <.link navigate={~p"/conversations"} class="catalog__empty-link">
                  start one →
                </.link>
              </p>
            </div>

            <div :if={@cards != []} class="catalog__row catalog__row--header">
              <span>Call №</span>
              <span>Front</span>
              <span>Drawer</span>
              <span>Filed</span>
            </div>

            <.link
              :for={card <- @cards}
              navigate={~p"/cards/#{card.id}"}
              class="catalog__row"
              id={"catalog-card-#{card.id}"}
            >
              <span class="catalog__row-call">{card.call_number}</span>
              <span class="catalog__row-front">{card.front}</span>
              <span class="catalog__row-drawer">{short_drawer(card.drawer)}</span>
              <span class="catalog__row-filed">{format_date(card.inserted_at)}</span>
            </.link>
          </section>
        </div>

        <footer class="catalog__foot">
          <span>Showing {length(@cards)} of {@total}</span>
        </footer>
      </main>
    </Layouts.app>
    """
  end

  # ── helpers ─────────────────────────────────────────────────────────

  defp assign_cards(socket) do
    actor = socket.assigns.current_user
    filters = socket.assigns.filters

    cards =
      Archive.list_filed_cards(actor.id,
        query: filters.query,
        drawer: filters.drawer,
        card_type: filters.card_type,
        tag_id: filters.tag_id,
        limit: 100
      )

    assign(socket, :cards, cards)
  end

  defp atomize_filter(nil, _allowed), do: nil
  defp atomize_filter("", _allowed), do: nil

  defp atomize_filter(value, allowed) when is_binary(value) do
    case String.to_existing_atom(value) do
      atom -> if atom in allowed, do: atom, else: nil
    end
  rescue
    ArgumentError -> nil
  end

  defp catalog_path(current_filters, override) do
    merged =
      current_filters
      |> Map.merge(override |> Enum.into(%{}))

    params =
      []
      |> maybe_param("q", merged[:query])
      |> maybe_param("drawer", merged[:drawer])
      |> maybe_param("type", merged[:card_type])
      |> maybe_param("tag", merged[:tag_id])

    if params == [] do
      "/catalog"
    else
      "/catalog?" <> URI.encode_query(params)
    end
  end

  defp maybe_param(acc, _key, nil), do: acc
  defp maybe_param(acc, _key, ""), do: acc
  defp maybe_param(acc, key, val) when is_atom(val), do: acc ++ [{key, Atom.to_string(val)}]
  defp maybe_param(acc, key, val) when is_binary(val), do: acc ++ [{key, val}]

  defp any_filter?(%{query: q, drawer: d, card_type: t, tag_id: tag}) do
    (is_binary(q) and q != "") or not is_nil(d) or not is_nil(t) or not is_nil(tag)
  end

  defp format_filters(%{} = filters, tags) do
    [
      filters.drawer && drawer_name(filters.drawer),
      filters.card_type && to_string(filters.card_type),
      filters.tag_id && tag_name(filters.tag_id, tags),
      filters.query != "" && filters.query && "\"#{filters.query}\""
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" · ")
  end

  defp tag_name(tag_id, tags) do
    case Enum.find(tags, &(&1.tag.id == tag_id)) do
      nil -> nil
      %{tag: tag} -> "#" <> tag.name
    end
  end

  defp pluralize(1, sing, _), do: sing
  defp pluralize(_, _, plur), do: plur

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d %b %y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d %b %y")
  defp format_date(_), do: ""

  defp short_drawer(:ANT), do: "DR.01"
  defp short_drawer(:CLA), do: "DR.02"
  defp short_drawer(:MED), do: "DR.03"
  defp short_drawer(:REN), do: "DR.04"
  defp short_drawer(:EAR), do: "DR.05"
  defp short_drawer(:MOD), do: "DR.06"
  defp short_drawer(:CON), do: "DR.07"
  defp short_drawer(other), do: to_string(other)
end
