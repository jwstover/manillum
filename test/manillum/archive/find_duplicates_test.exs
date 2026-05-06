defmodule Manillum.Archive.FindDuplicatesTest do
  @moduledoc """
  Tests for `Manillum.Archive.find_duplicates/3` (Slice 6 / M-24).

  Embeddings are seeded directly via `Ash.Seed.seed!` so the test
  doesn't depend on the OpenAI embedding job firing. Vectors are
  hand-crafted so cosine distance between them is deterministic:

      [1.0, 0.0, …]  vs  [1.0, 0.0, …]  → 0.0 (identical)
      [1.0, 0.0, …]  vs  [0.0, 1.0, …]  → 1.0 (orthogonal)
      [1.0, 0.0, …]  vs  [-1.0, 0.0, …] → 2.0 (opposite)

  Lets us exercise threshold filtering and sort order without
  hand-counting cosine values.
  """

  use Manillum.DataCase, async: false

  alias Manillum.Archive
  alias Manillum.Archive.Card

  @dim 1536

  setup do
    user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "find_dups_test@example.com"})
    other_user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "find_dups_other@example.com"})
    {:ok, user: user, other_user: other_user}
  end

  describe "find_duplicates/3" do
    test "returns nearest filed card first under threshold", %{user: user} do
      query_vec = unit_vector(0)

      near = seed_filed_card(user, "NEAR", unit_vector(0))
      _far = seed_filed_card(user, "FAR", unit_vector(1))

      assert [near.id] == Archive.find_duplicates(user.id, query_vec, threshold: 0.25)
    end

    test "orders multiple matches by cosine distance ascending", %{user: user} do
      # Three cards: identical, slightly off-axis, more off-axis.
      identical = seed_filed_card(user, "IDENT", unit_vector(0))
      close = seed_filed_card(user, "CLOSE", normalized([0.95, 0.05]))
      farther = seed_filed_card(user, "FARTHER", normalized([0.7, 0.7]))

      query = unit_vector(0)

      assert [identical.id, close.id, farther.id] ==
               Archive.find_duplicates(user.id, query, threshold: 0.5, limit: 5)
    end

    test "respects threshold cutoff", %{user: user} do
      # cosine distance to query is 1.0 — outside any sane threshold
      _orthogonal = seed_filed_card(user, "ORTHO", unit_vector(1))

      assert [] == Archive.find_duplicates(user.id, unit_vector(0), threshold: 0.25)
    end

    test "respects limit", %{user: user} do
      for i <- 1..5 do
        seed_filed_card(user, "DUP-#{i}", normalized([1.0, i * 0.001]))
      end

      ids = Archive.find_duplicates(user.id, unit_vector(0), threshold: 0.5, limit: 2)
      assert length(ids) == 2
    end

    test "excludes ids in :exclude_ids", %{user: user} do
      a = seed_filed_card(user, "A", unit_vector(0))
      b = seed_filed_card(user, "B", normalized([0.99, 0.01]))

      assert [b.id] ==
               Archive.find_duplicates(user.id, unit_vector(0),
                 threshold: 0.25,
                 exclude_ids: [a.id]
               )
    end

    test "scopes to the requesting user's archive", %{user: user, other_user: other} do
      _theirs = seed_filed_card(other, "THEIRS", unit_vector(0))
      mine = seed_filed_card(user, "MINE", unit_vector(0))

      assert [mine.id] == Archive.find_duplicates(user.id, unit_vector(0), threshold: 0.25)
    end

    test "ignores draft cards by default", %{user: user} do
      _draft = seed_card(user, %{slug: "DRAFT", status: :draft, embedding: unit_vector(0)})
      filed = seed_filed_card(user, "FILED", unit_vector(0))

      assert [filed.id] == Archive.find_duplicates(user.id, unit_vector(0), threshold: 0.25)
    end

    test "includes drafts when :status is widened", %{user: user} do
      draft = seed_card(user, %{slug: "DRAFT", status: :draft, embedding: unit_vector(0)})
      filed = seed_filed_card(user, "FILED", unit_vector(0))

      ids =
        Archive.find_duplicates(user.id, unit_vector(0),
          threshold: 0.25,
          status: [:draft, :filed]
        )

      assert Enum.sort(ids) == Enum.sort([draft.id, filed.id])
    end

    test "skips cards without an embedding (e.g. before the async job runs)", %{user: user} do
      _no_embedding = seed_card(user, %{slug: "PENDING", status: :filed, embedding: nil})
      with_embedding = seed_filed_card(user, "READY", unit_vector(0))

      assert [with_embedding.id] ==
               Archive.find_duplicates(user.id, unit_vector(0), threshold: 0.25)
    end

    test "returns [] when query embedding is nil", %{user: user} do
      _seed = seed_filed_card(user, "ANY", unit_vector(0))
      assert [] == Archive.find_duplicates(user.id, nil)
    end

    test "returns [] when no cards match", %{user: user} do
      assert [] == Archive.find_duplicates(user.id, unit_vector(0))
    end

    test "accepts an Ash.Vector embedding directly", %{user: user} do
      seeded = seed_filed_card(user, "VEC", unit_vector(0))
      {:ok, vector} = Ash.Vector.new(unit_vector(0))

      assert [seeded.id] == Archive.find_duplicates(user.id, vector, threshold: 0.25)
    end
  end

  ## Helpers

  defp seed_filed_card(user, slug, embedding) do
    seed_card(user, %{slug: slug, status: :filed, embedding: embedding})
  end

  defp seed_card(user, overrides) do
    base = %{
      user_id: user.id,
      drawer: :ANT,
      date_token: "1177BC",
      slug: "DEFAULT",
      card_type: :event,
      front: "F",
      back: "B"
    }

    Ash.Seed.seed!(Card, Map.merge(base, overrides))
  end

  defp unit_vector(axis) when axis < @dim do
    Enum.map(0..(@dim - 1), fn i -> if i == axis, do: 1.0, else: 0.0 end)
  end

  defp normalized(prefix) when is_list(prefix) do
    padded = prefix ++ List.duplicate(0.0, @dim - length(prefix))
    norm = :math.sqrt(Enum.reduce(padded, 0.0, fn v, acc -> acc + v * v end))
    Enum.map(padded, &(&1 / norm))
  end
end
