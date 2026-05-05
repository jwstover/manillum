defmodule Manillum.Archive.Capture.Changes.RunCataloging do
  @moduledoc """
  Orchestration change for `Manillum.Archive.Capture.:catalog`. Drives the
  cataloging pipeline end-to-end on behalf of the AshOban scan trigger:

    1. Flip the capture's status to `:cataloging` (visibility marker;
       subsequent scheduler ticks won't re-pick the row since the trigger
       filters on `:pending`).
    2. Call `:extract_drafts` (prompt-backed action) to get a list of
       `Manillum.Archive.Cataloging.DraftCard`s from the source text.
    3. For each DraftCard: detect call-number collision via
       `:propose_call_number` and persist a `:draft` Card row with
       `capture_id` set when the segments are unique.
    4. Set the changeset's final status to `:catalogued` (with
       `error_reason` summarizing any per-draft skips) or `:failed` on
       unrecoverable error.
    5. Broadcast `:cards_drafted` / `:cards_drafting_failed` on
       `"user:\#{user_id}:cataloging"` per spec §7.3.

  ## Deferred (per Slice 4 review)

  Semantic duplicate detection (embedding `back` text and looking up
  cosine-similar existing cards via `Archive.find_duplicates/2`) is
  deferred to a follow-on. When that lands, the per-draft step in #3
  gains an embedding + dup-candidate fetch, and the persisted draft
  carries `duplicate_candidate_ids`. Likewise, entity-autostub and the
  `:cards_drafted`-with-autostub-flags broadcast wait on Stream B
  task 5 (`:autostub`).

  ## Why the change goes through `before_action`

  We can't run an HTTP call (the LLM) inside the action's transaction
  without holding a DB lock for ~10s. The `:catalog` action sets
  `transaction? false` to opt out, and the change runs in a
  `before_action` hook so the final `:catalogued | :failed` status
  flip is what the changeset commits when it returns. The intermediate
  `:cataloging` write is a separate `:mark_cataloging` action call.
  """

  use Ash.Resource.Change

  alias Manillum.Archive.Capture
  alias Manillum.Archive.Card

  require Logger

  @cataloging_topic_prefix "user:"

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &run/1)
  end

  defp run(changeset) do
    capture = changeset.data

    # Best-effort visibility marker. If this update fails (e.g. the row was
    # already mutated by something else), we still proceed; the final
    # status flip is what matters for the trigger filter.
    _ = mark_cataloging(capture)

    case extract_and_persist(capture) do
      {:ok, %{persisted: persisted, skipped: skipped}} ->
        broadcast_drafted(capture, persisted)

        changeset
        |> Ash.Changeset.force_change_attribute(:status, :catalogued)
        |> maybe_set_skipped_note(skipped)

      {:error, reason} ->
        broadcast_failed(capture, reason)

        changeset
        |> Ash.Changeset.force_change_attribute(:status, :failed)
        |> Ash.Changeset.force_change_attribute(:error_reason, format_reason(reason))
    end
  end

  defp mark_cataloging(capture) do
    capture
    |> Ash.Changeset.for_update(:mark_cataloging, %{})
    |> Ash.update(authorize?: false)
  end

  defp extract_and_persist(capture) do
    with {:ok, drafts} <- extract_drafts(capture) do
      {persisted, skipped} = persist_drafts(capture, drafts)
      {:ok, %{persisted: persisted, skipped: skipped}}
    end
  end

  defp extract_drafts(capture) do
    Capture
    |> Ash.ActionInput.for_action(:extract_drafts, %{source_text: capture.source_text})
    |> Ash.run_action(authorize?: false)
  end

  defp persist_drafts(capture, drafts) do
    Enum.reduce(drafts, {[], []}, fn draft, {persisted, skipped} ->
      case persist_draft(capture, draft) do
        {:ok, card} -> {persisted ++ [card], skipped}
        {:skipped, reason} -> {persisted, skipped ++ [{draft, reason}]}
      end
    end)
  end

  defp persist_draft(capture, draft) do
    case propose_call_number(capture.user_id, draft) do
      {:resolved, _proposal} ->
        create_card(capture, draft)

      {:collision, existing_card_id} ->
        Logger.info(fn ->
          "[cataloging] capture=#{capture.id} skipping draft slug=#{draft.slug} " <>
            "drawer=#{draft.drawer} date_token=#{draft.date_token} — " <>
            "collides with card #{existing_card_id}"
        end)

        {:skipped, {:collision, existing_card_id}}

      {:error, reason} ->
        Logger.warning(fn ->
          "[cataloging] capture=#{capture.id} propose_call_number failed for " <>
            "slug=#{draft.slug}: #{inspect(reason)}"
        end)

        {:skipped, {:propose_call_number_error, reason}}
    end
  end

  defp propose_call_number(user_id, draft) do
    Card
    |> Ash.ActionInput.for_action(:propose_call_number, %{
      user_id: user_id,
      drawer: draft.drawer,
      date_token: draft.date_token,
      slug: draft.slug,
      card_type: draft.card_type
    })
    |> Ash.run_action(authorize?: false)
    |> case do
      {:ok, %{status: :resolved} = proposal} -> {:resolved, proposal}
      {:ok, %{status: :collision, existing_card_id: id}} -> {:collision, id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_card(capture, draft) do
    attrs = %{
      user_id: capture.user_id,
      capture_id: capture.id,
      drawer: draft.drawer,
      date_token: draft.date_token,
      slug: draft.slug,
      card_type: draft.card_type,
      front: draft.front,
      back: draft.back,
      pending_autostubs: draft.entities || []
    }

    Card
    |> Ash.Changeset.for_create(:draft, attrs)
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, card} ->
        {:ok, card}

      {:error, reason} ->
        Logger.warning(fn ->
          "[cataloging] capture=#{capture.id} draft create failed for slug=#{draft.slug}: " <>
            inspect(reason)
        end)

        {:skipped, {:create_failed, reason}}
    end
  end

  defp maybe_set_skipped_note(changeset, []), do: changeset

  defp maybe_set_skipped_note(changeset, skipped) do
    note = "Skipped #{length(skipped)} draft(s) due to call-number collisions or create errors."
    Ash.Changeset.force_change_attribute(changeset, :error_reason, note)
  end

  defp broadcast_drafted(capture, persisted) do
    Phoenix.PubSub.broadcast(
      Manillum.PubSub,
      topic(capture.user_id),
      {:cards_drafted,
       %{
         capture_id: capture.id,
         conversation_id: capture.conversation_id,
         draft_ids: Enum.map(persisted, & &1.id)
       }}
    )
  end

  defp broadcast_failed(capture, reason) do
    Phoenix.PubSub.broadcast(
      Manillum.PubSub,
      topic(capture.user_id),
      {:cards_drafting_failed,
       %{
         capture_id: capture.id,
         reason: format_reason(reason)
       }}
    )
  end

  defp topic(user_id), do: "#{@cataloging_topic_prefix}#{user_id}:cataloging"

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
