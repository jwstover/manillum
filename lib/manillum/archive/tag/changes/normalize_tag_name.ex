defmodule Manillum.Archive.Tag.Changes.NormalizeTagName do
  @moduledoc """
  Sets `normalized_name` to a downcased copy of `name`. Drives the
  case-insensitive identity (`:unique_normalized_name`) so the same tag
  spelled with different casing — `"Bronze Age"`, `"bronze age"`,
  `"BRONZE AGE"` — collapses to a single row per user.

  The user-facing `name` is left untouched, so the first call's casing
  wins on the persisted row.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      nil ->
        changeset

      name when is_binary(name) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :normalized_name,
          String.downcase(name)
        )
    end
  end
end
