defmodule Manillum.Archive.Link.Changes.CanonicalizeSeeAlsoOrder do
  @moduledoc """
  When `kind == :see_also`, swaps `from_card_id` and `to_card_id` so the
  smaller UUID is always `from_card_id`. This collapses an A→B and a B→A
  see_also into a single row under the `:unique_directed_link` identity:
  `:see_also` is semantically symmetric (if A see-also B, then B see-also
  A), so storing one row per pair avoids divergence between the two
  directions.

  `:derived_from` and `:references` remain directional and pass through
  unchanged — "A derived from B" does not imply "B derived from A".
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    with :see_also <- Ash.Changeset.get_attribute(changeset, :kind),
         from when is_binary(from) <- Ash.Changeset.get_attribute(changeset, :from_card_id),
         to when is_binary(to) <- Ash.Changeset.get_attribute(changeset, :to_card_id),
         true <- from > to do
      changeset
      |> Ash.Changeset.force_change_attribute(:from_card_id, to)
      |> Ash.Changeset.force_change_attribute(:to_card_id, from)
    else
      _ -> changeset
    end
  end
end
