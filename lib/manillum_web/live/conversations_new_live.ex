defmodule ManillumWeb.ConversationsNewLive do
  @moduledoc """
  Stub for the "start a new conversation" route. Real chat lives in
  `ConversationsLive`; this route exists in the IA so the shell nav can
  surface a dedicated "new chat" entry point. M-2 already ships chat
  itself, so this stub will likely fold into the existing chat view in a
  later slice (or stay as a focused composer landing page).
  """
  use ManillumWeb, :live_view

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "New conversation")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="conversations">
      <.stub_page
        kicker="● Manillum · conversations · new"
        title="A blank conversation is waiting."
        lede="This is where a fresh chat with Livy will start. The composer below would focus on mount; sending the first message creates a Conversation and routes you to its persistent thread."
        affordances={[
          "Bottom-pinned composer with “Ask Livy —” kicker, ready to type.",
          "First message creates a Conversation and pushes to /conversations/:id.",
          "Shell nav stays visible so leaving without sending is one click.",
          "(Real flow lives in ConversationsLive — Slice 2 / M-2.)"
        ]}
      />
    </Layouts.app>
    """
  end
end
