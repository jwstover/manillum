defmodule ManillumWeb.HomeLive do
  @moduledoc """
  Placeholder root page. Will become the "Today" view once Streams D / E / F land.
  """

  use ManillumWeb, :live_view

  on_mount {ManillumWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.topbar active="today" tagline="— a quiet workshop">
        <:tab id="today" href={~p"/"}>Today</:tab>
        <:tab id="components" href="/dev/components">Components</:tab>
      </.topbar>
      <.era_band pin_year={2026} pin_label="today" />

      <ManillumWeb.Layouts.flash_group flash={@flash} />

      <main class="home">
        <.kicker>● Manillum · today</.kicker>
        <h1 class="home__title">Nothing filed yet.</h1>
        <p class="home__lede">
          This is the placeholder for the Today view. Once chat, capture, and
          filing land, your latest conversation, fresh drafts, and the day's
          review queue will surface here.
        </p>
      </main>
    </.page>

    <style>
      .home {
        padding: 4rem var(--margin-page-x) 6rem;
        max-width: 60rem;
      }
      .home__title {
        font-family: var(--font-display);
        font-size: 3rem;
        font-weight: 500;
        font-style: italic;
        letter-spacing: -0.012em;
        line-height: 1.05;
        color: var(--color-ink);
        margin: 0.75rem 0 1.5rem;
      }
      .home__lede {
        font-family: var(--font-body);
        font-size: 1.0625rem;
        line-height: 1.6;
        color: var(--color-ink-soft);
        max-width: 36rem;
      }
    </style>
    """
  end
end
