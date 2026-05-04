defmodule Manillum.Archive.Card.ProposeCallNumber do
  @moduledoc """
  Implementation of `Card.propose_call_number`. Pure read operation: queries
  for an existing card with the same segments and either resolves to a
  formatted call_number or returns disambiguation suggestions per §7.4.
  """

  use Ash.Resource.Actions.Implementation

  alias Manillum.Archive.Card
  alias Manillum.Archive.Card.CallNumberProposal

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    %{drawer: drawer, date_token: date_token, slug: slug, card_type: card_type, user_id: user_id} =
      input.arguments

    if collision?(user_id, drawer, date_token, slug) do
      {:ok,
       %CallNumberProposal{
         status: :collision,
         suggestions: suggest(slug, card_type, date_token)
       }}
    else
      {:ok,
       %CallNumberProposal{
         status: :resolved,
         drawer: drawer,
         date_token: date_token,
         slug: slug,
         call_number: Card.format_call_number(drawer, date_token, slug)
       }}
    end
  end

  defp collision?(user_id, drawer, _date_token, slug) do
    # Per §7.4 the unique constraint is (user_id, drawer, slug) — date_token
    # can vary between two cards that nonetheless collide.
    Card
    |> Ash.Query.filter(user_id == ^user_id and drawer == ^drawer and slug == ^slug)
    |> Ash.exists?(authorize?: false)
  end

  # §7.4 disambiguation strategy, by card_type. The specific values are
  # starting points — a UI / future iteration can offer richer choices
  # (e.g., real letters for actual person names, real qualifiers for
  # places). For MVP we provide the right *shape* of suggestion.

  defp suggest(slug, :person, _date_token) do
    # Letter suffix — A through C as starter alternatives.
    for <<letter <- "ABC">> do
      %{
        slug: slug <> "-" <> <<letter>>,
        reason: "Letter-suffix disambiguator (person card type, §7.4)."
      }
    end
  end

  defp suggest(slug, :event, date_token) when is_binary(date_token) and date_token != "" do
    # Year disambiguator using the supplied date_token.
    [
      %{
        slug: slug <> "-" <> date_token,
        reason: "Date disambiguator (#{date_token}) for event card type (§7.4)."
      }
    ]
  end

  defp suggest(slug, :place, _date_token) do
    # Qualifier suffix — placeholder; the user typically replaces ALT with
    # a region or era qualifier (e.g., ALEXANDRIA-EGY, ALEXANDRIA-TROAS).
    [
      %{
        slug: slug <> "-ALT",
        reason: "Qualifier disambiguator for place card type (§7.4) — replace ALT with a region or era."
      }
    ]
  end

  defp suggest(slug, _other_card_type, _date_token) do
    # Numeric fallback for concept / source / date / artifact / event-without-date.
    for n <- 2..4 do
      %{slug: slug <> "-" <> Integer.to_string(n), reason: "Numeric disambiguator."}
    end
  end
end
