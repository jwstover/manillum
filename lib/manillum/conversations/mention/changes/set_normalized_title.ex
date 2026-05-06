defmodule Manillum.Conversations.Mention.Changes.SetNormalizedTitle do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :title) do
      nil ->
        changeset

      title when is_binary(title) ->
        Ash.Changeset.change_attribute(
          changeset,
          :normalized_title,
          title |> String.trim() |> String.downcase()
        )
    end
  end
end
