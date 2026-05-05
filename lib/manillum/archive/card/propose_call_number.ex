defmodule Manillum.Archive.Card.ProposeCallNumber do
  @moduledoc """
  Implementation of `Card.propose_call_number`. Pure read action: queries
  for an existing card with the same segments and returns either a
  resolved proposal with the formatted call_number, or a collision flag
  with the existing card's id.

  This action does not invent alternative slugs. Generating a meaningful
  disambiguator requires content context (the card's `front` / `back` /
  entities, plus the colliding card's content) which lives at the
  cataloging pipeline (Slice 4) or in the filing tray (Stream E). See
  spec §7.4 for the disambiguation style guide.
  """

  use Ash.Resource.Actions.Implementation

  alias Manillum.Archive.Card
  alias Manillum.Archive.Card.CallNumberProposal

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    %{drawer: drawer, date_token: date_token, slug: slug, user_id: user_id} = input.arguments

    case existing_card(user_id, drawer, date_token, slug) do
      nil ->
        {:ok,
         %CallNumberProposal{
           status: :resolved,
           drawer: drawer,
           date_token: date_token,
           slug: slug,
           call_number: Card.format_call_number(drawer, date_token, slug)
         }}

      %Card{id: id} ->
        {:ok, %CallNumberProposal{status: :collision, existing_card_id: id}}
    end
  end

  defp existing_card(user_id, drawer, date_token, slug) do
    Card
    |> Ash.Query.filter(
      user_id == ^user_id and drawer == ^drawer and date_token == ^date_token and slug == ^slug
    )
    |> Ash.Query.select([:id])
    |> Ash.read_one!(authorize?: false)
  end
end
