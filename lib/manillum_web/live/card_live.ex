defmodule ManillumWeb.CardLive do
  @moduledoc """
  Stub for `/cards/:id` — single card detail view. Real implementation
  lands with Stream F / Slice 11 (M-29).
  """
  use ManillumWeb, :live_view

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:card_id, id)
     |> assign(:page_title, "Card · " <> id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="catalog">
      <.stub_page
        kicker={"● Manillum · card · " <> @card_id}
        title="A single card, in detail."
        lede="This is where a filed card opens to its full surface — recto and verso, call number, drawer label, tags and entities, see-also links, and provenance back to the conversation it came from."
        affordances={[
          "Recto / verso card render at signature size.",
          "Call number, drawer label, tags, and entities visible.",
          "“See also” cross-links to related cards (Stream B).",
          "Provenance link back to the source conversation/message.",
          "Edit, rename (creates a redirect), and review-history actions."
        ]}
      />
    </Layouts.app>
    """
  end
end
