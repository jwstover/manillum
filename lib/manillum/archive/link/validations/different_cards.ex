defmodule Manillum.Archive.Link.Validations.DifferentCards do
  @moduledoc """
  Rejects a Link whose `from_card_id` equals its `to_card_id`. A card
  linking to itself is a meaningless edge in the see-also / derived-from
  / references graph.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    from = Ash.Changeset.get_attribute(changeset, :from_card_id)
    to = Ash.Changeset.get_attribute(changeset, :to_card_id)

    if from && to && from == to do
      {:error, field: :to_card_id, message: "cannot link a card to itself"}
    else
      :ok
    end
  end
end
