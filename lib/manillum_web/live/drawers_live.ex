defmodule ManillumWeb.DrawersLive do
  @moduledoc """
  Stub for `/drawers` (era-based filing cabinet) and `/drawers/:drawer`
  (single drawer detail). Real implementation lands with Stream F /
  Slice 11 (M-29).
  """
  use ManillumWeb, :live_view

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"drawer" => drawer}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:drawer, drawer)
     |> assign(:page_title, "Drawer · #{drawer}")
     |> assign(:live_action, :show)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:drawer, nil)
     |> assign(:page_title, "Drawers")
     |> assign(:live_action, :index)}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="drawers">
      <.stub_page
        kicker={"● Manillum · drawer · " <> @drawer}
        title={"Drawer #{@drawer}"}
        lede="Single-drawer detail. Cards filed under this drawer, sorted chronologically by date_token, with the drawer's color bullet and stamp visible at scale."
        affordances={[
          "Drawer label header with color bullet and era range.",
          "Cards sorted by date_token (oldest → newest by default).",
          "Hover-to-skim card previews; click to open /cards/:id.",
          "Filter by tag or card type within the drawer.",
          "Empty-state copy if no cards filed in this drawer yet."
        ]}
      />
    </Layouts.app>
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="drawers">
      <.stub_page
        kicker="● Manillum · drawers"
        title="Browse the cabinet, era by era."
        lede="This is where the filed cards organize themselves into era-shaped drawers — Antiquity, Classical, Middle Ages, … Now. Each drawer shows its color, label, and a count of cards inside."
        affordances={[
          "Eight drawers laid out as colour-bulleted labels.",
          "Card counts and most-recent-filed timestamps per drawer.",
          "Era band echoes the active drawer with a brass tick.",
          "Click a drawer to open /drawers/:drawer.",
          "Empty drawers visible but dimmed."
        ]}
      />
    </Layouts.app>
    """
  end
end
