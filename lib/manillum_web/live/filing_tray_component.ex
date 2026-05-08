defmodule ManillumWeb.FilingTrayComponent do
  @moduledoc """
  Right-column rail for cataloging activity on the conversation surface.
  Three states drive the body:

    * `:empty`    — no drafts, nothing in flight, no failure. The rail
                    renders an italic invite (and the parent column
                    collapses to zero width via CSS).
    * `:drafting` — at least one Capture is in flight (LiveView pushed
                    `{:capture_submitted, …}` after `Manillum.Archive.submit/2`).
                    Renders a single `cataloging_indicator` — no per-draft
                    skeletons.
    * `:review`   — at least one persisted draft Card. Renders the draft
                    list, with the cataloging indicator above when more
                    captures are still in flight.

  Parent (`ConversationsLive`) owns the PubSub subscription and the
  send_update fan-out:

    * `{:capture_submitted, %{capture_id: id}}` — pushed after the LV
      successfully creates a Capture. Tray records the in-flight id.
    * `{:cards_drafted, %{capture_id: id, draft_ids: [...]}}` — broadcast
      from the cataloging pipeline. Tray pops the in-flight id, appends
      the persisted drafts.
    * `{:cards_drafting_failed, %{capture_id: id, reason: ...}}` —
      broadcast on pipeline failure. Tray pops the in-flight id and
      raises the failure banner.
  """
  use ManillumWeb, :live_component

  import ManillumWeb.ManillumComponents

  alias Manillum.Archive
  alias Manillum.Archive.Card
  alias Phoenix.LiveView.JS

  @impl true
  def update(%{action: {:capture_submitted, %{capture_id: capture_id}}}, socket) do
    {:ok, track_in_flight(socket, capture_id)}
  end

  def update(%{action: {:cards_drafted, %{draft_ids: ids} = payload}}, socket) do
    new_drafts =
      socket.assigns.actor
      |> list_drafts()
      |> Enum.filter(&(&1.id in ids))

    socket =
      Enum.reduce(new_drafts, socket, fn draft, acc ->
        stream_insert(acc, :drafts, draft, at: 0)
      end)

    {:ok,
     socket
     |> bump_count(length(new_drafts))
     |> drop_in_flight(payload[:capture_id])}
  end

  def update(%{action: {:cards_drafting_failed, payload}}, socket) do
    {:ok,
     socket
     |> assign(:failure, payload)
     |> drop_in_flight(payload[:capture_id])}
  end

  def update(assigns, socket) do
    drafts = list_drafts(assigns.actor)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:draft_count, length(drafts))
     |> assign_new(:failure, fn -> nil end)
     |> assign_new(:dismissed, fn -> false end)
     |> assign_new(:in_flight, fn -> MapSet.new() end)
     |> stream(:drafts, drafts)}
  end

  @impl true
  def handle_event("discard", %{"id" => id}, socket) do
    actor = socket.assigns.actor

    with {:ok, card} <- Ash.get(Card, id, actor: actor),
         :ok <- Archive.discard_card(card, actor: actor) do
      {:noreply,
       socket
       |> stream_delete(:drafts, card)
       |> bump_count(-1)}
    else
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("dismiss_failure", _params, socket) do
    {:noreply, assign(socket, :failure, nil)}
  end

  def handle_event("close_tray", _params, socket) do
    {:noreply, assign(socket, :dismissed, true)}
  end

  def handle_event("reopen_tray", _params, socket) do
    {:noreply, assign(socket, :dismissed, false)}
  end

  defp track_in_flight(socket, nil), do: socket

  defp track_in_flight(socket, capture_id) do
    update(socket, :in_flight, &MapSet.put(&1, capture_id))
  end

  defp drop_in_flight(socket, nil), do: socket

  defp drop_in_flight(socket, capture_id) do
    update(socket, :in_flight, &MapSet.delete(&1, capture_id))
  end

  # Maintain a parallel counter alongside the stream — Phoenix LV streams
  # are write-only, so the component can't ask "how many entries do you
  # currently have?". Tracking count here lets the tray collapse cleanly
  # once the last draft is discarded.
  defp bump_count(socket, delta) do
    update(socket, :draft_count, &max(0, &1 + delta))
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:tray_state, tray_state(assigns))
      |> assign(:in_flight_count, MapSet.size(assigns.in_flight))

    ~H"""
    <div class={tray_container_classes(@dismissed, @draft_count, @failure, @in_flight_count)} id={@id}>
      <button
        :if={@draft_count > 0 || @in_flight_count > 0 || @failure}
        type="button"
        class="filing_tray__spine"
        phx-click="reopen_tray"
        phx-target={@myself}
        aria-label="Reopen filing tray"
        tabindex={if @dismissed, do: "0", else: "-1"}
      >
        <span class="filing_tray__spine-rule" aria-hidden="true"></span>
        <span class="filing_tray__spine-label">
          {spine_label(@draft_count, @in_flight_count, @failure)}
        </span>
      </button>
      <.filing_tray
        state={@tray_state}
        kicker={tray_kicker(@draft_count, @in_flight_count, @failure)}
        sub={tray_sub(@tray_state, @failure)}
        close_event="close_tray"
        close_target={@myself}
      >
        <div :if={@failure} class="filing_tray__failure">
          <.icon name="hero-exclamation-triangle-micro" /> {failure_message(@failure)}
          <button type="button" phx-click="dismiss_failure" phx-target={@myself}>dismiss</button>
        </div>

        <.cataloging_indicator
          :if={@in_flight_count > 0 && is_nil(@failure)}
          sub={cataloging_sub(@in_flight_count)}
        />

        <div id={@id <> "-drafts"} phx-update="stream">
          <article
            :for={{dom_id, draft} <- @streams.drafts}
            id={dom_id}
            class="filing_tray__draft"
            phx-remove={JS.transition("filing_tray__draft--discarding", time: 280)}
          >
            <.draft_card draft={draft} target={@myself} />
          </article>
        </div>
      </.filing_tray>
    </div>
    """
  end

  attr :draft, :map, required: true
  attr :target, :any, required: true

  defp draft_card(assigns) do
    ~H"""
    <.card face={:draft}>
      <div class="filing_tray__draft-head">
        <.call_number inline>{@draft.call_number}</.call_number>
      </div>
      <.drawer_label>{drawer_name(@draft.drawer)}</.drawer_label>
      <div class="filing_tray__draft-front">{@draft.front}</div>
      <div class="filing_tray__draft-back">{@draft.back}</div>
      <div class="filing_tray__draft-actions">
        <.action_pill>
          <.icon name="hero-archive-box-micro" /> file
        </.action_pill>
        <.action_pill variant={:ghost}>edit</.action_pill>
        <button
          type="button"
          class="action_pill action_pill--bare"
          phx-click="discard"
          phx-value-id={@draft.id}
          phx-target={@target}
        >
          discard
        </button>
      </div>
    </.card>
    """
  end

  defp list_drafts(actor) do
    Archive.list_drafts!(actor: actor)
  end

  # State-resolution: failure dominates (review state shows the banner +
  # any persisted drafts), then drafts (review), then in-flight (drafting),
  # then empty.
  defp tray_state(%{failure: failure}) when not is_nil(failure), do: :review
  defp tray_state(%{draft_count: n}) when n > 0, do: :review

  defp tray_state(%{in_flight: in_flight}) do
    if MapSet.size(in_flight) > 0, do: :drafting, else: :empty
  end

  defp tray_kicker(0, _in_flight, _failure), do: "FILING TRAY"
  defp tray_kicker(1, _in_flight, _failure), do: "FILING TRAY · 1 DRAFT"
  defp tray_kicker(n, _in_flight, _failure), do: "FILING TRAY · #{n} DRAFTS"

  defp tray_sub(_state, failure) when not is_nil(failure), do: "Cataloging failed"

  defp tray_sub(:empty, _failure),
    do: "Anything you file from the conversation will land here."

  defp tray_sub(:drafting, _failure),
    do: "Cataloging in the background — keep chatting if you like."

  defp tray_sub(:review, _failure),
    do: "Drafts ready to file. Trust Livy and file all, or review each."

  defp cataloging_sub(1), do: "1 capture in flight"
  defp cataloging_sub(n), do: "#{n} captures in flight"

  # Vertical mono label for the dismissed-state spine. Mirrors the design's
  # `★ Filing tray · 3 · show ›` line. Drops the count when there are no
  # persisted drafts (the spine still surfaces while drafts are forming
  # or a failure is showing — the count would just read "0").
  defp spine_label(0, in_flight, failure)
       when in_flight > 0 or not is_nil(failure),
       do: "★ Filing tray · show ›"

  defp spine_label(n, _in_flight, _failure), do: "★ Filing tray · #{n} · show ›"

  # Always keep the stream container in the DOM so Phoenix LV streams
  # don't lose their items on close/reopen. Visibility is driven via
  # CSS classes the parent layout can target.
  defp tray_container_classes(dismissed, draft_count, failure, in_flight_count) do
    empty? = draft_count == 0 and is_nil(failure) and in_flight_count == 0

    [
      "filing_tray__container",
      empty? && "filing_tray__container--empty",
      dismissed && "filing_tray__container--dismissed"
    ]
  end

  defp failure_message(%{reason: reason}) when is_binary(reason), do: reason
  defp failure_message(%{reason: reason}), do: inspect(reason)
  defp failure_message(_), do: "Something went wrong while cataloging."

  defp drawer_name(:ANT), do: "Dr. 01 · Antiquity"
  defp drawer_name(:CLA), do: "Dr. 02 · Classical"
  defp drawer_name(:MED), do: "Dr. 03 · Medieval"
  defp drawer_name(:REN), do: "Dr. 04 · Renaissance"
  defp drawer_name(:EAR), do: "Dr. 05 · Early Modern"
  defp drawer_name(:MOD), do: "Dr. 06 · Modern"
  defp drawer_name(:CON), do: "Dr. 07 · Contemporary"
  defp drawer_name(other), do: to_string(other)
end
