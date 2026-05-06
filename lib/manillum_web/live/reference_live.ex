defmodule ManillumWeb.ReferenceLive do
  @moduledoc """
  Stub for `/reference` — indexes of People, Places, Sources, Themes.
  Real implementation lands with Stream F / Slice 11 (M-29).
  """
  use ManillumWeb, :live_view

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Reference")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="reference">
      <.stub_page
        kicker="● Manillum · reference"
        title="People, places, sources, themes."
        lede="The cross-reference layer — every entity mentioned across filed cards, grouped into four index families. A way into the archive that doesn't go through search."
        affordances={[
          "Four tabs: People · Places · Sources · Themes.",
          "Each entity surfaces a list of cards that mention it.",
          "Click an entity to filter Catalog by that entity.",
          "Tag-shaped index pulled from Card.tags (user-curated).",
          "Entity index pulled from Card.entities (LLM-extracted)."
        ]}
      />
    </Layouts.app>
    """
  end
end
