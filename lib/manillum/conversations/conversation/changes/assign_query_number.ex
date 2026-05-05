defmodule Manillum.Conversations.Conversation.Changes.AssignQueryNumber do
  @moduledoc """
  Assigns a sequential `query_number` to a new conversation, scoped to the
  user. Used as the `QRY №` display per spec §4.

  Counts the user's existing conversations and adds 1. Concurrent creates that
  pick the same number will collide on the `:unique_query_number_per_user`
  identity; the loser can retry. Sufficient for the single-user MVP.
  """
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      user_id =
        Ash.Changeset.get_attribute(changeset, :user_id) ||
          (context.actor && context.actor.id)

      count =
        Manillum.Conversations.Conversation
        |> Ash.Query.filter(user_id == ^user_id)
        |> Ash.count!(authorize?: false)

      Ash.Changeset.force_change_attribute(changeset, :query_number, count + 1)
    end)
  end
end
