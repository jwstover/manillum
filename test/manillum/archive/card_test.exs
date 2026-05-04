defmodule Manillum.Archive.CardTest do
  use Manillum.DataCase, async: false

  alias Manillum.Archive.Card

  describe "resource shape" do
    test "is registered on Manillum.Archive" do
      assert Card in Ash.Domain.Info.resources(Manillum.Archive)
    end

    test "has the §4 attributes" do
      attrs = Card |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

      for name <- [
            :id,
            :drawer,
            :date_token,
            :slug,
            :card_type,
            :front,
            :back,
            :status,
            :inserted_at,
            :updated_at
          ] do
        assert name in attrs, "expected attribute #{inspect(name)} on Card"
      end
    end

    test "has unique_drawer_slug identity on (user_id, drawer, slug) per §7.4" do
      identity =
        Card |> Ash.Resource.Info.identities() |> Enum.find(&(&1.name == :unique_drawer_slug))

      assert identity, "expected :unique_drawer_slug identity"
      assert identity.keys == [:user_id, :drawer, :slug]
    end

    test "has a call_number calculation" do
      calcs = Card |> Ash.Resource.Info.calculations() |> Enum.map(& &1.name)
      assert :call_number in calcs
    end
  end

  describe "call_number calculation" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "card_test@example.com"})

      card =
        Ash.Seed.seed!(Card, %{
          user_id: user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "COLLAPSE",
          card_type: :event,
          front: "What does it mean to call the Bronze Age collapse a 'systems collapse'?",
          back: "Between 1200 and 1150 BCE, ..."
        })

      {:ok, card: card}
    end

    test "produces the §7.4 format byte-for-byte (U+00B7 separator, single spaces)",
         %{card: card} do
      loaded = Ash.load!(card, :call_number)

      # String-level
      assert loaded.call_number == "ANT · 1177BC · COLLAPSE"

      # Byte-level: U+00B7 is encoded as the two-byte sequence 0xC2 0xB7 in
      # UTF-8, flanked by 0x20 (space). This is the format-drift gate from
      # §7.4 — Stream C and Stream D both depend on this exact encoding.
      assert <<"ANT", 0x20, 0xC2, 0xB7, 0x20, "1177BC", 0x20, 0xC2, 0xB7, 0x20, "COLLAPSE">> =
               loaded.call_number
    end
  end

  describe ":draft action" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "draft_test@example.com"})
      {:ok, user: user}
    end

    test "creates a card in :draft status with the supplied segments", %{user: user} do
      attrs = %{
        user_id: user.id,
        drawer: :ANT,
        date_token: "1177BC",
        slug: "COLLAPSE",
        card_type: :event,
        front: "What is the Bronze Age collapse?",
        back: "Between 1200 and 1150 BCE, ..."
      }

      assert {:ok, card} =
               Card
               |> Ash.Changeset.for_create(:draft, attrs)
               |> Ash.create()

      assert card.status == :draft
      assert card.drawer == :ANT
      assert card.date_token == "1177BC"
      assert card.slug == "COLLAPSE"
    end

    test "rejects an invalid drawer enum", %{user: user} do
      attrs = %{
        user_id: user.id,
        drawer: :NOPE,
        date_token: "1177BC",
        slug: "COLLAPSE",
        card_type: :event,
        front: "F",
        back: "B"
      }

      assert {:error, _} =
               Card
               |> Ash.Changeset.for_create(:draft, attrs)
               |> Ash.create()
    end

    test "rejects when a required field is missing", %{user: user} do
      attrs = %{
        user_id: user.id,
        drawer: :ANT,
        # date_token missing
        slug: "COLLAPSE",
        card_type: :event,
        front: "F",
        back: "B"
      }

      assert {:error, _} =
               Card
               |> Ash.Changeset.for_create(:draft, attrs)
               |> Ash.create()
    end
  end

  describe ":propose_call_number action" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "propose_test@example.com"})

      seed_card = fn slug, card_type ->
        Ash.Seed.seed!(Card, %{
          user_id: user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: slug,
          card_type: card_type,
          front: "F",
          back: "B"
        })
      end

      {:ok, user: user, seed_card: seed_card}
    end

    test "happy path resolves with the formatted call_number", %{user: user} do
      assert {:ok,
              %Manillum.Archive.Card.CallNumberProposal{
                status: :resolved,
                drawer: :ANT,
                date_token: "1177BC",
                slug: "COLLAPSE",
                call_number: call_number,
                suggestions: []
              }} =
               Manillum.Archive.Card
               |> Ash.ActionInput.for_action(:propose_call_number, %{
                 user_id: user.id,
                 drawer: :ANT,
                 date_token: "1177BC",
                 slug: "COLLAPSE",
                 card_type: :event
               })
               |> Ash.run_action()

      # Format-drift gate: same byte-level check as the calculation test.
      assert <<"ANT", 0x20, 0xC2, 0xB7, 0x20, "1177BC", 0x20, 0xC2, 0xB7, 0x20, "COLLAPSE">> =
               call_number
    end

    test "person collision suggests letter-suffix slugs", %{user: user, seed_card: seed_card} do
      _existing = seed_card.("CAESAR", :person)

      assert {:ok,
              %{status: :collision, suggestions: suggestions}} =
               Manillum.Archive.Card
               |> Ash.ActionInput.for_action(:propose_call_number, %{
                 user_id: user.id,
                 drawer: :ANT,
                 date_token: "1177BC",
                 slug: "CAESAR",
                 card_type: :person
               })
               |> Ash.run_action()

      assert length(suggestions) > 0

      for %{slug: slug, reason: reason} <- suggestions do
        assert String.starts_with?(slug, "CAESAR-"), "expected letter-suffix slug, got #{slug}"
        # Letter suffixes are a single uppercase A–Z.
        assert Regex.match?(~r/^CAESAR-[A-Z]$/, slug)
        assert reason =~ "person"
      end
    end

    test "event collision suggests a year-disambiguated slug",
         %{user: user, seed_card: seed_card} do
      _existing = seed_card.("THERMOPYLAE", :event)

      assert {:ok, %{status: :collision, suggestions: suggestions}} =
               Manillum.Archive.Card
               |> Ash.ActionInput.for_action(:propose_call_number, %{
                 user_id: user.id,
                 drawer: :ANT,
                 date_token: "480BC",
                 slug: "THERMOPYLAE",
                 card_type: :event
               })
               |> Ash.run_action()

      assert Enum.any?(suggestions, fn %{slug: slug, reason: reason} ->
               slug == "THERMOPYLAE-480BC" and reason =~ "Date"
             end)
    end

    test "place collision suggests a qualifier-style slug",
         %{user: user, seed_card: seed_card} do
      _existing = seed_card.("ALEXANDRIA", :place)

      assert {:ok, %{status: :collision, suggestions: suggestions}} =
               Manillum.Archive.Card
               |> Ash.ActionInput.for_action(:propose_call_number, %{
                 user_id: user.id,
                 drawer: :ANT,
                 date_token: "1177BC",
                 slug: "ALEXANDRIA",
                 card_type: :place
               })
               |> Ash.run_action()

      assert Enum.any?(suggestions, fn %{slug: slug, reason: reason} ->
               String.starts_with?(slug, "ALEXANDRIA-") and reason =~ "place"
             end)
    end
  end

  describe "format_call_number/3" do
    test "produces the §7.4 format byte-for-byte" do
      result = Manillum.Archive.Card.format_call_number(:ANT, "1177BC", "COLLAPSE")
      assert result == "ANT · 1177BC · COLLAPSE"

      assert <<"ANT", 0x20, 0xC2, 0xB7, 0x20, "1177BC", 0x20, 0xC2, 0xB7, 0x20, "COLLAPSE">> =
               result
    end
  end
end
