defmodule Manillum.Archive.Card.Autostub do
  @moduledoc """
  Implementation of `Card.:autostub`. For each entity name in `entities`,
  checks whether the user's archive already covers it (case-insensitively
  matching the slug or front of any Card, or the name of any Tag) and
  creates a placeholder `:draft` Card stub when no match is found.

  Returns the ids of newly-created stubs. Re-running with the same input
  is a no-op once stubs have been created — the heuristic catches the
  newly-created `Autostub: <name>` fronts and matching slugs on the
  second pass.
  """

  use Ash.Resource.Actions.Implementation

  alias Manillum.Archive.Card
  alias Manillum.Archive.Tag

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    %{user_id: user_id, entities: entities} = input.arguments

    existing = load_existing_signals(user_id)

    created_ids =
      entities
      |> Enum.uniq_by(&normalize/1)
      |> Enum.reject(&matches_existing?(&1, existing))
      |> Enum.flat_map(&create_stub(user_id, &1))

    {:ok, created_ids}
  end

  defp load_existing_signals(user_id) do
    card_signals =
      Card
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.select([:slug, :front])
      |> Ash.read!(authorize?: false)
      |> Enum.flat_map(fn card -> [normalize(card.slug), normalize(card.front)] end)

    tag_signals =
      Tag
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.select([:normalized_name])
      |> Ash.read!(authorize?: false)
      |> Enum.map(&normalize(&1.normalized_name))

    card_signals ++ tag_signals
  end

  defp matches_existing?(name, existing_signals) do
    needle = normalize(name)
    needle != "" and Enum.any?(existing_signals, &String.contains?(&1, needle))
  end

  defp create_stub(user_id, name) do
    Card
    |> Ash.Changeset.for_create(:draft, %{
      user_id: user_id,
      drawer: :CON,
      date_token: "CON",
      slug: slugify(name),
      card_type: :concept,
      front: "Autostub: #{name}",
      back: "Stub created during cataloging — needs content."
    })
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, card} -> [card.id]
      {:error, _} -> []
    end
  end

  defp normalize(string) when is_binary(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[-_]+/, " ")
    |> String.trim()
  end

  defp slugify(name) when is_binary(name) do
    name
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9\s-]+/, "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.join("-")
  end
end
