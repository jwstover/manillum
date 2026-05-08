defmodule Manillum.Archive.Card.Changes.Rename do
  @moduledoc """
  Implements `Card.:rename` — captures the card's pre-rename segments,
  syncs `:collision_card_id` for the new segments, lets the changeset
  apply the new ones, and after the update writes a
  `CallNumberRedirect` row pointing the old segments at the now-renamed
  card. Finally broadcasts `{:card_renamed, old, new}` on
  `"user:\#{user_id}:archive"` per spec §7.3.

  No-op when the action runs without changing any segment (the redirect
  write is skipped, but a broadcast is still sent — this is observable
  and matches the §7.3 contract).
  """

  use Ash.Resource.Change

  alias Manillum.Archive.CallNumberRedirect
  alias Manillum.Archive.Card
  alias Manillum.Archive.Card.CallNumberProposal

  require Ash.Query
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    old_drawer = changeset.data.drawer
    old_date_token = changeset.data.date_token
    old_slug = changeset.data.slug
    user_id = changeset.data.user_id
    self_id = changeset.data.id

    changeset
    |> Ash.Changeset.before_action(fn cs ->
      new_drawer = Ash.Changeset.get_attribute(cs, :drawer)
      new_date_token = Ash.Changeset.get_attribute(cs, :date_token)
      new_slug = Ash.Changeset.get_attribute(cs, :slug)
      card_type = Ash.Changeset.get_attribute(cs, :card_type)

      collision_id =
        compute_collision(user_id, new_drawer, new_date_token, new_slug, card_type, self_id)

      Ash.Changeset.force_change_attribute(cs, :collision_card_id, collision_id)
    end)
    |> Ash.Changeset.after_action(fn _changeset, card ->
      old_call_number = Card.format_call_number(old_drawer, old_date_token, old_slug)
      new_call_number = Card.format_call_number(card.drawer, card.date_token, card.slug)

      if old_call_number != new_call_number do
        record_redirect(user_id, old_drawer, old_date_token, old_slug, card.id)
      end

      Phoenix.PubSub.broadcast(
        Manillum.PubSub,
        "user:#{user_id}:archive",
        {:card_renamed, old_call_number, new_call_number}
      )

      {:ok, card}
    end)
  end

  # Re-runs `:propose_call_number` for the new segments and returns the
  # colliding card's id (or nil if no collision). Self-matches are
  # filtered out — a card collides with another card, not itself.
  defp compute_collision(user_id, drawer, date_token, slug, card_type, self_id) do
    Card
    |> Ash.ActionInput.for_action(:propose_call_number, %{
      user_id: user_id,
      drawer: drawer,
      date_token: date_token,
      slug: slug,
      card_type: card_type || :event
    })
    |> Ash.run_action(authorize?: false)
    |> case do
      {:ok, %CallNumberProposal{status: :collision, existing_card_id: id}}
      when id != self_id ->
        id

      _ ->
        nil
    end
  end

  defp record_redirect(user_id, drawer, date_token, slug, current_card_id) do
    CallNumberRedirect
    |> Ash.Changeset.for_create(:record, %{
      user_id: user_id,
      drawer: drawer,
      date_token: date_token,
      slug: slug,
      current_card_id: current_card_id
    })
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, redirect} ->
        {:ok, redirect}

      {:error, reason} ->
        Logger.warning(fn ->
          "[rename] redirect write failed for user=#{user_id} " <>
            "old=(#{drawer}, #{date_token}, #{slug}) → card=#{current_card_id}: " <>
            inspect(reason)
        end)

        {:error, reason}
    end
  end
end
