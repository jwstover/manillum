defmodule Manillum.Archive.AutostubTest do
  use Manillum.DataCase, async: false

  alias Manillum.Archive
  alias Manillum.Archive.Card

  require Ash.Query

  defp make_user(email) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{email: email})
  end

  defp count_cards(user_id) do
    Card
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read!(authorize?: false)
    |> length()
  end

  describe "Card.pending_autostubs attribute" do
    test "is part of the §4 schema with default []" do
      attr = Ash.Resource.Info.attribute(Card, :pending_autostubs)

      assert attr, "expected :pending_autostubs attribute on Card"
      assert attr.default == []
      assert attr.allow_nil? == false
    end

    test "the :draft action accepts pending_autostubs" do
      user = make_user("pending_autostubs@example.com")

      assert {:ok, card} =
               Archive.draft_card(%{
                 user_id: user.id,
                 drawer: :ANT,
                 date_token: "1177BC",
                 slug: "COLLAPSE",
                 card_type: :event,
                 front: "F",
                 back: "B",
                 pending_autostubs: ["Mycenae", "Hittites"]
               })

      assert card.pending_autostubs == ["Mycenae", "Hittites"]
    end
  end

  describe ":autostub action" do
    setup do
      {:ok, user: make_user("autostub@example.com")}
    end

    test "creates one stub per missing entity", %{user: user} do
      assert {:ok, ids} = Archive.autostub(user.id, ["Meiji government", "Iwakura Mission"])

      assert length(ids) == 2

      stubs =
        Card
        |> Ash.Query.filter(id in ^ids)
        |> Ash.read!(authorize?: false)

      slugs = stubs |> Enum.map(& &1.slug) |> Enum.sort()
      assert slugs == ["IWAKURA-MISSION", "MEIJI-GOVERNMENT"]

      for stub <- stubs do
        assert stub.user_id == user.id
        assert stub.drawer == :CON
        assert stub.date_token == "CON"
        assert stub.card_type == :concept
        assert stub.status == :draft
        assert String.starts_with?(stub.front, "Autostub: ")
        assert stub.back =~ "Stub created during cataloging"
      end
    end

    test "is idempotent on repeat calls", %{user: user} do
      {:ok, ids_first} = Archive.autostub(user.id, ["Meiji government", "Iwakura Mission"])
      assert length(ids_first) == 2

      assert {:ok, ids_second} =
               Archive.autostub(user.id, ["Meiji government", "Iwakura Mission"])

      assert ids_second == []
      assert count_cards(user.id) == 2
    end

    test "skips entities matching an existing card slug", %{user: user} do
      _existing =
        Ash.Seed.seed!(Card, %{
          user_id: user.id,
          drawer: :MOD,
          date_token: "1868",
          slug: "MEIJI-GOVERNMENT",
          card_type: :event,
          front: "What was the Meiji government?",
          back: "The post-1868 imperial government of Japan."
        })

      assert {:ok, ids} = Archive.autostub(user.id, ["Meiji government", "Iwakura Mission"])

      stubs =
        Card
        |> Ash.Query.filter(id in ^ids)
        |> Ash.read!(authorize?: false)

      slugs = stubs |> Enum.map(& &1.slug)
      assert slugs == ["IWAKURA-MISSION"]
    end

    test "skips entities matching an existing tag name", %{user: user} do
      {:ok, _} = Archive.find_or_create_tag(user.id, "Meiji government")

      assert {:ok, ids} = Archive.autostub(user.id, ["Meiji government", "Iwakura Mission"])

      stubs =
        Card
        |> Ash.Query.filter(id in ^ids)
        |> Ash.read!(authorize?: false)

      assert Enum.map(stubs, & &1.slug) == ["IWAKURA-MISSION"]
    end

    test "is per-user — another user's card doesn't shadow", %{user: user} do
      other = make_user("autostub_other@example.com")

      _theirs =
        Ash.Seed.seed!(Card, %{
          user_id: other.id,
          drawer: :MOD,
          date_token: "1868",
          slug: "MEIJI-GOVERNMENT",
          card_type: :event,
          front: "What was the Meiji government?",
          back: "Post-1868 government of Japan."
        })

      assert {:ok, ids} = Archive.autostub(user.id, ["Meiji government"])
      assert length(ids) == 1
    end

    test "deduplicates entities by case-insensitive name", %{user: user} do
      assert {:ok, ids} =
               Archive.autostub(user.id, [
                 "Meiji government",
                 "MEIJI government",
                 "meiji GOVERNMENT"
               ])

      assert length(ids) == 1
    end

    test "real card filed at a slug + earlier stub deleted: only Iwakura is created on re-run",
         %{user: user} do
      # Empty archive, autostub seeds two stubs.
      {:ok, [meiji_id, iwakura_id]} =
        Archive.autostub(user.id, ["Meiji government", "Iwakura Mission"])

      meiji_stub = Ash.get!(Card, meiji_id, authorize?: false)
      iwakura_stub = Ash.get!(Card, iwakura_id, authorize?: false)

      # File the Meiji stub (promote draft → filed).
      {:ok, _filed} = Archive.file_card(meiji_stub)

      # Delete the Iwakura stub.
      :ok = Ash.destroy!(iwakura_stub, authorize?: false)

      # Re-run autostub. Meiji is now blocked by the filed real card; Iwakura
      # has no match, so only it gets a stub.
      assert {:ok, [new_id]} =
               Archive.autostub(user.id, ["Meiji government", "Iwakura Mission"])

      new_stub = Ash.get!(Card, new_id, authorize?: false)
      assert new_stub.slug == "IWAKURA-MISSION"
    end
  end

  describe "RunCataloging passes entities to pending_autostubs" do
    test "draft Card carries the entities the LLM extracted" do
      alias Manillum.AI.ReqLLMStub

      ReqLLMStub.reset()

      ReqLLMStub.put_response([
        %{
          "card_type" => "event",
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "COLLAPSE",
          "front" => "F",
          "back" => "B",
          "tags" => [],
          "entities" => ["Mycenae", "Hittites", "Ugarit"]
        }
      ])

      user = make_user("pipeline_autostub@example.com")

      {:ok, capture} =
        Archive.submit(%{
          user_id: user.id,
          source_text: "Bronze Age collapse, ~1177 BC",
          scope: :whole
        })

      {:ok, _catalogued} =
        capture
        |> Ash.Changeset.for_update(:catalog, %{})
        |> Ash.update()

      [card] =
        Card
        |> Ash.Query.filter(capture_id == ^capture.id)
        |> Ash.read!(authorize?: false)

      assert card.pending_autostubs == ["Mycenae", "Hittites", "Ugarit"]
    end
  end
end
