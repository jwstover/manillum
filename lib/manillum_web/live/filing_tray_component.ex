defmodule ManillumWeb.FilingTrayComponent do
  @moduledoc """
  Slide-out panel rendering the user's draft Cards. Slice 10A scope:
  load drafts on mount, append on `:cards_drafted` PubSub events, surface
  `:cards_drafting_failed` as an inline banner, and let the user discard
  drafts. File / edit / dup-resolution / undo land in 10B/10C.

  Parent (`ConversationsLive`) owns the PubSub subscription and forwards
  cataloging broadcasts via `send_update/2` with an `:action` key.
  """
  use ManillumWeb, :live_component

  import ManillumWeb.ManillumComponents

  alias Manillum.Archive
  alias Manillum.Archive.Card

  @impl true
  def update(%{action: {:cards_drafted, %{draft_ids: ids}}}, socket) do
    new_drafts =
      socket.assigns.actor
      |> list_drafts()
      |> Enum.filter(&(&1.id in ids))

    socket =
      Enum.reduce(new_drafts, socket, fn draft, acc ->
        stream_insert(acc, :drafts, draft, at: 0)
      end)

    {:ok, bump_count(socket, length(new_drafts))}
  end

  def update(%{action: {:cards_drafting_failed, payload}}, socket) do
    {:ok, assign(socket, :failure, payload)}
  end

  def update(assigns, socket) do
    drafts = list_drafts(assigns.actor)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:draft_count, length(drafts))
     |> assign_new(:failure, fn -> nil end)
     |> assign_new(:dismissed, fn -> false end)
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

  # Maintain a parallel counter alongside the stream — Phoenix LV streams
  # are write-only, so the component can't ask "how many entries do you
  # currently have?". Tracking count here lets the tray collapse cleanly
  # once the last draft is discarded.
  defp bump_count(socket, delta) do
    update(socket, :draft_count, &max(0, &1 + delta))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={tray_container_classes(@dismissed, @draft_count, @failure)} id={@id}>
      <button
        :if={@dismissed && @draft_count > 0}
        type="button"
        class="filing_tray__reopen"
        phx-click="reopen_tray"
        phx-target={@myself}
        aria-label="Reopen filing tray"
      >
        drafts ({@draft_count}) <.icon name="hero-chevron-left-mini" />
      </button>
      <.filing_tray
        state={:review}
        kicker={tray_kicker(@draft_count)}
        title={tray_title(@failure)}
        close_event="close_tray"
        close_target={@myself}
      >
        <div :if={@failure} class="filing_tray__failure">
          <.icon name="hero-exclamation-triangle-micro" /> {failure_message(@failure)}
          <button type="button" phx-click="dismiss_failure" phx-target={@myself}>dismiss</button>
        </div>

        <div id={@id <> "-drafts"} phx-update="stream">
          <article
            :for={{dom_id, draft} <- @streams.drafts}
            id={dom_id}
            class="filing_tray__draft"
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
        <.meta_label>{provenance_label(@draft)}</.meta_label>
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

  defp tray_title(nil), do: "Drafts to review"
  defp tray_title(_failure), do: "Cataloging failed"

  defp tray_kicker(0), do: "FILING TRAY"
  defp tray_kicker(1), do: "FILING TRAY · 1 DRAFT"
  defp tray_kicker(n), do: "FILING TRAY · #{n} DRAFTS"

  # Always keep the stream container in the DOM so Phoenix LV streams
  # don't lose their items on close/reopen. Visibility is driven via
  # CSS classes the parent layout can target.
  defp tray_container_classes(dismissed, count, failure) do
    [
      "filing_tray__container",
      (count == 0 && is_nil(failure)) && "filing_tray__container--empty",
      dismissed && "filing_tray__container--dismissed"
    ]
  end

  defp failure_message(%{reason: reason}) when is_binary(reason), do: reason
  defp failure_message(%{reason: reason}), do: inspect(reason)
  defp failure_message(_), do: "Something went wrong while cataloging."

  # Slice 10A: minimal provenance — "FROM CHAT" when sourced from a
  # Capture, else "DRAFT". Slice 10B will reach back to the source
  # conversation for the QRY № / paragraph index per the /dev/components
  # mockup (`QRY 89 · ¶2`).
  defp provenance_label(%{capture: %{id: id}}) when is_binary(id), do: "FROM CHAT"
  defp provenance_label(_), do: "DRAFT"

  defp drawer_name(:ANT), do: "Dr. 01 · Antiquity"
  defp drawer_name(:CLA), do: "Dr. 02 · Classical"
  defp drawer_name(:MED), do: "Dr. 03 · Medieval"
  defp drawer_name(:REN), do: "Dr. 04 · Renaissance"
  defp drawer_name(:EAR), do: "Dr. 05 · Early Modern"
  defp drawer_name(:MOD), do: "Dr. 06 · Modern"
  defp drawer_name(:CON), do: "Dr. 07 · Contemporary"
  defp drawer_name(other), do: to_string(other)
end
