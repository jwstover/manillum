defmodule ManillumWeb.CatalogLive do
  @moduledoc """
  Stub for `/catalog` — the search-first card list. Real implementation
  lands with Stream F / Slice 11 (M-29).
  """
  use ManillumWeb, :live_view

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Catalog")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="catalog">
      <.stub_page
        kicker="● Manillum · catalog"
        title="Search the whole catalog."
        lede="This is where every filed card lives, retrievable by what's on it. Free-text search across fronts, backs, and entities; filter by drawer, era, tag, or card type."
        affordances={[
          "Search input matching slugs, fronts, backs, and entities.",
          "Filter chips: drawer · era · tag · card type · recently filed.",
          "Result list rendered as compact card previews with call numbers.",
          "“+ COMPOSE” entry point for manual card authoring (M-37).",
          "Click a result to open /cards/:id."
        ]}
      />
    </Layouts.app>
    """
  end
end
