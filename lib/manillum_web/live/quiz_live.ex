defmodule ManillumWeb.QuizLive do
  @moduledoc """
  Stub for `/quiz` — the SRS review queue. Real implementation lands
  with Stream G / Slice 12 (M-30) and the QuizLive UI (M-31).
  """
  use ManillumWeb, :live_view

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Quiz")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="quiz">
      <.stub_page
        kicker="● Manillum · quiz"
        title="Today's review queue."
        lede="This is where Spaced Repetition surfaces cards you're due to review — front first, then verso, then a self-graded recall response that adjusts the SM-2 schedule."
        affordances={[
          "Card-at-a-time review: front presented, reveal verso on click.",
          "Self-grade buttons: again / hard / good / easy.",
          "Daily counter: due today, reviewed today.",
          "“Skip” without affecting the schedule.",
          "Empty-state copy when nothing is due."
        ]}
      />
    </Layouts.app>
    """
  end
end
