defmodule Manillum.Archive.Card.Changes.Rename do
  @moduledoc """
  Implements `Card.:rename` — captures the card's pre-rename segments,
  lets the changeset apply the new ones, and after the update writes a
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

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    old_drawer = changeset.data.drawer
    old_date_token = changeset.data.date_token
    old_slug = changeset.data.slug
    user_id = changeset.data.user_id

    Ash.Changeset.after_action(changeset, fn _changeset, card ->
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
