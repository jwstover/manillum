defmodule Manillum.Archive.TagTest do
  use Manillum.DataCase, async: false

  alias Manillum.Archive
  alias Manillum.Archive.Card
  alias Manillum.Archive.CardTag
  alias Manillum.Archive.Tag

  require Ash.Query

  defp make_user(email) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{email: email})
  end

  defp seed_card(user, slug) do
    Ash.Seed.seed!(Card, %{
      user_id: user.id,
      drawer: :ANT,
      date_token: "1177BC",
      slug: slug,
      card_type: :event,
      front: "F",
      back: "B"
    })
  end

  describe "resource shape" do
    test "is registered on Manillum.Archive" do
      assert Tag in Ash.Domain.Info.resources(Manillum.Archive)
    end

    test "has §4 attributes including normalized_name" do
      attrs = Tag |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

      for name <- [:id, :name, :normalized_name, :inserted_at, :updated_at] do
        assert name in attrs, "expected attribute #{inspect(name)} on Tag"
      end
    end

    test "has unique_normalized_name identity on (user_id, normalized_name)" do
      identity =
        Tag
        |> Ash.Resource.Info.identities()
        |> Enum.find(&(&1.name == :unique_normalized_name))

      assert identity, "expected :unique_normalized_name identity"
      assert identity.keys == [:user_id, :normalized_name]
    end
  end

  describe "find_or_create" do
    setup do
      {:ok, user: make_user("tag_foc@example.com")}
    end

    test "creates a new tag with normalized_name downcased and name preserved", %{user: user} do
      assert {:ok, tag} = Archive.find_or_create_tag(user.id, "Bronze Age")

      assert tag.name == "Bronze Age"
      assert tag.normalized_name == "bronze age"
      assert tag.user_id == user.id
    end

    test "is case-insensitive: second call returns the first row", %{user: user} do
      assert {:ok, first} = Archive.find_or_create_tag(user.id, "Bronze Age")
      assert {:ok, second} = Archive.find_or_create_tag(user.id, "bronze age")
      assert {:ok, third} = Archive.find_or_create_tag(user.id, "BRONZE AGE")

      assert first.id == second.id
      assert first.id == third.id

      # The first call's casing wins on the persisted row.
      assert second.name == "Bronze Age"
      assert third.name == "Bronze Age"
    end

    test "is idempotent: re-calling does not create duplicate rows", %{user: user} do
      assert {:ok, _} = Archive.find_or_create_tag(user.id, "Eastern Mediterranean")
      assert {:ok, _} = Archive.find_or_create_tag(user.id, "Eastern Mediterranean")
      assert {:ok, _} = Archive.find_or_create_tag(user.id, "eastern mediterranean")

      tags =
        Tag
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.read!(authorize?: false)

      assert length(tags) == 1
    end

    test "is per-user: same name in two users creates two rows" do
      alice = make_user("alice_tag@example.com")
      bob = make_user("bob_tag@example.com")

      assert {:ok, alice_tag} = Archive.find_or_create_tag(alice.id, "Bronze Age")
      assert {:ok, bob_tag} = Archive.find_or_create_tag(bob.id, "Bronze Age")

      refute alice_tag.id == bob_tag.id
      assert alice_tag.user_id == alice.id
      assert bob_tag.user_id == bob.id
    end
  end

  describe "tag_card / untag_card" do
    setup do
      user = make_user("card_tag@example.com")
      card = seed_card(user, "TAG-CARD")
      {:ok, tag} = Archive.find_or_create_tag(user.id, "Bronze Age")

      {:ok, user: user, card: card, tag: tag}
    end

    test "associates a card with a tag", %{card: card, tag: tag} do
      assert {:ok, join} = Archive.tag_card(card.id, tag.id)

      assert join.card_id == card.id
      assert join.tag_id == tag.id
    end

    test "is idempotent on repeat calls", %{card: card, tag: tag} do
      assert {:ok, _} = Archive.tag_card(card.id, tag.id)
      assert {:ok, _} = Archive.tag_card(card.id, tag.id)

      joins =
        CardTag
        |> Ash.Query.filter(card_id == ^card.id and tag_id == ^tag.id)
        |> Ash.read!(authorize?: false)

      assert length(joins) == 1
    end

    test "Card.tags many_to_many returns the tag", %{card: card, tag: tag} do
      assert {:ok, _} = Archive.tag_card(card.id, tag.id)

      loaded = Ash.load!(card, :tags)
      assert [%Tag{} = loaded_tag] = loaded.tags
      assert loaded_tag.id == tag.id
    end

    test "Tag.cards many_to_many returns the card", %{card: card, tag: tag} do
      assert {:ok, _} = Archive.tag_card(card.id, tag.id)

      loaded = Ash.load!(tag, :cards)
      assert [%Card{} = loaded_card] = loaded.cards
      assert loaded_card.id == card.id
    end

    test "untag_card removes the join row", %{card: card, tag: tag} do
      assert {:ok, join} = Archive.tag_card(card.id, tag.id)

      assert :ok = Archive.untag_card(join)

      joins =
        CardTag
        |> Ash.Query.filter(card_id == ^card.id and tag_id == ^tag.id)
        |> Ash.read!(authorize?: false)

      assert joins == []
    end
  end
end
