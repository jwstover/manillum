defmodule Manillum.Archive.Link.Validations.SameUser do
  @moduledoc """
  Rejects a Link whose `from_card` and `to_card` belong to different
  users. The card archive is single-user; cross-user edges would leak
  one user's archive into another's see-also graph.
  """

  use Ash.Resource.Validation

  alias Manillum.Archive.Card

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    from = Ash.Changeset.get_attribute(changeset, :from_card_id)
    to = Ash.Changeset.get_attribute(changeset, :to_card_id)

    cond do
      is_nil(from) or is_nil(to) ->
        :ok

      from == to ->
        # Different-cards validation will fire; nothing to add here.
        :ok

      true ->
        do_validate(from, to)
    end
  end

  defp do_validate(from_id, to_id) do
    cards =
      Card
      |> Ash.Query.filter(id in [^from_id, ^to_id])
      |> Ash.Query.select([:id, :user_id])
      |> Ash.read!(authorize?: false)

    case cards do
      [%{user_id: u1}, %{user_id: u2}] when u1 == u2 ->
        :ok

      [_, _] ->
        {:error,
         field: :to_card_id, message: "from_card and to_card must belong to the same user"}

      _ ->
        # One or both cards don't exist; let the FK constraint surface
        # the error rather than producing a misleading message here.
        :ok
    end
  end
end
