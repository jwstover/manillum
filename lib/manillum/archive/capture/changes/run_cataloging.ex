defmodule Manillum.Archive.Capture.Changes.RunCataloging do
  @moduledoc """
  Orchestration change for `Manillum.Archive.Capture.:catalog`. Drives the
  cataloging pipeline end-to-end on behalf of the AshOban scan trigger:

    1. Flip the capture's status to `:cataloging` (visibility marker;
       subsequent scheduler ticks won't re-pick the row since the trigger
       filters on `:pending`).
    2. Call `:extract_drafts` (prompt-backed action) to get a list of
       `Manillum.Archive.Cataloging.DraftCard`s from the source text.
    3. Embed each draft's `back` text in a single batched call to
       `Manillum.AI.Embedding.OpenAI`.
    4. For each DraftCard:
         - check call-number collision via `:propose_call_number`
         - run cosine-similarity search via
           `Manillum.Archive.find_duplicates/3`
         - persist a `:draft` Card row with `capture_id`,
           `duplicate_candidate_ids`, and (on call-number collision)
           `collision_card_id` set. The filing tray (Slice 10 / M-28)
           surfaces both signals so the user can pick disambiguating
           segments or merge intent before filing.
    5. Set the changeset's final status to `:catalogued` (with
       `error_reason` summarizing any per-draft create errors) or
       `:failed` on unrecoverable error.
    6. Broadcast `:cards_drafted` / `:cards_drafting_failed` on
       `"user:\#{user_id}:cataloging"` per spec §7.3.

  ## Why call-number collisions land as drafts now

  Slice 4 silently skipped collision drafts and recorded a note in
  `Capture.error_reason`. With dup-detection landing here in Slice 6,
  the colliding-call-number branch persists the draft instead and flags
  it via `Card.collision_card_id`. The filing tray gets a real signal
  to reconcile against rather than a phantom skipped result.

  ## Why `back` is embedded twice per cataloged card

  Each draft's `back` is embedded once here (upfront, to query
  `find_duplicates` against the existing archive) and a second time
  ~1s later by the AshAI `vectorize` block's `:ash_oban` trigger
  (after the row exists, to populate `Card.embedding` for *future*
  dup-queries against this card). Same model, same input, same vector.

  Intentional redundancy: the two paths answer different questions
  (this draft's similarity vs this card's discoverability), and at
  MVP scale the redundant compute is ~$0.0000006 per card. See the
  2026-05-06 decision callout in the project index for the full
  trade-off.

  ## Why the change goes through `before_action`

  We can't run an HTTP call (the LLM) inside the action's transaction
  without holding a DB lock for ~10s. The `:catalog` action sets
  `transaction? false` to opt out, and the change runs in a
  `before_action` hook so the final `:catalogued | :failed` status
  flip is what the changeset commits when it returns. The intermediate
  `:cataloging` write is a separate `:mark_cataloging` action call.
  """

  use Ash.Resource.Change

  alias Manillum.AI.Embedding.OpenAI, as: Embedder
  alias Manillum.Archive
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
      embeddings = embed_drafts(capture, drafts)
      {persisted, skipped} = persist_drafts(capture, drafts, embeddings)
      {:ok, %{persisted: persisted, skipped: skipped}}
    end
  end

  defp extract_drafts(capture) do
    Capture
    |> Ash.ActionInput.for_action(:extract_drafts, %{source_text: capture.source_text})
    |> Ash.run_action(authorize?: false)
  end

  # Single batched embedding call across all drafts. On error, log and
  # fall through with `nil` embeddings — drafts still persist (without
  # `duplicate_candidate_ids`); the async vectorize trigger backfills
  # `Card.embedding` once the row is created, so dup-detection is just
  # delayed rather than lost.
  defp embed_drafts(capture, drafts) do
    inputs = Enum.map(drafts, & &1.back)

    case Embedder.generate(inputs, []) do
      {:ok, vectors} when length(vectors) == length(drafts) ->
        vectors

      {:ok, _vectors} ->
        Logger.warning(fn ->
          "[cataloging] capture=#{capture.id} embedding count mismatch — " <>
            "skipping dup-detection for this batch"
        end)

        List.duplicate(nil, length(drafts))

      {:error, reason} ->
        Logger.warning(fn ->
          "[cataloging] capture=#{capture.id} embedding call failed: #{inspect(reason)} — " <>
            "skipping dup-detection for this batch"
        end)

        List.duplicate(nil, length(drafts))
    end
  end

  defp persist_drafts(capture, drafts, embeddings) do
    drafts
    |> Enum.zip(embeddings)
    |> Enum.reduce({[], []}, fn {draft, embedding}, {persisted, skipped} ->
      case persist_draft(capture, draft, embedding) do
        {:ok, card} -> {persisted ++ [card], skipped}
        {:skipped, reason} -> {persisted, skipped ++ [{draft, reason}]}
      end
    end)
  end

  defp persist_draft(capture, draft, embedding) do
    case propose_call_number(capture.user_id, draft) do
      {:resolved, _proposal} ->
        candidates = Archive.find_duplicates(capture.user_id, embedding)
        create_card(capture, draft, %{duplicate_candidate_ids: candidates})

      {:collision, existing_card_id} ->
        Logger.info(fn ->
          "[cataloging] capture=#{capture.id} draft slug=#{draft.slug} " <>
            "drawer=#{draft.drawer} date_token=#{draft.date_token} — " <>
            "call-number collides with card #{existing_card_id}; " <>
            "persisting draft with collision flag"
        end)

        candidates = Archive.find_duplicates(capture.user_id, embedding)

        create_card(capture, draft, %{
          collision_card_id: existing_card_id,
          duplicate_candidate_ids: candidates
        })

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

  defp create_card(capture, draft, extra_attrs) do
    attrs =
      %{
        user_id: capture.user_id,
        capture_id: capture.id,
        drawer: draft.drawer,
        date_token: draft.date_token,
        slug: draft.slug,
        card_type: draft.card_type,
        front: draft.front,
        back: draft.back,
        entities: draft.entities || []
      }
      |> Map.merge(extra_attrs)

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
    note = "Skipped #{length(skipped)} draft(s) due to create errors."
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
