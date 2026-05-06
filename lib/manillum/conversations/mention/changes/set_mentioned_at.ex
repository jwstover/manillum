defmodule Manillum.Conversations.Mention.Changes.SetMentionedAt do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :mentioned_at) do
      nil ->
        Ash.Changeset.change_attribute(
          changeset,
          :mentioned_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )

      _ ->
        changeset
    end
  end
end
