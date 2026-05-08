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

    test "has unique_call_number identity on (user_id, drawer, date_token, slug) per §7.4" do
      identity =
        Card |> Ash.Resource.Info.identities() |> Enum.find(&(&1.name == :unique_call_number))

      assert identity, "expected :unique_call_number identity"
      assert identity.keys == [:user_id, :drawer, :date_token, :slug]
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
                existing_card_id: nil
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

    test "collision returns the existing card's id", %{user: user, seed_card: seed_card} do
      existing = seed_card.("CAESAR", :person)

      assert {:ok,
              %Manillum.Archive.Card.CallNumberProposal{
                status: :collision,
                existing_card_id: existing_id,
                # All resolved-only fields are nil on a collision
                drawer: nil,
                date_token: nil,
                slug: nil,
                call_number: nil
              }} =
               Manillum.Archive.Card
               |> Ash.ActionInput.for_action(:propose_call_number, %{
                 user_id: user.id,
                 drawer: :ANT,
                 date_token: "1177BC",
                 slug: "CAESAR",
                 card_type: :person
               })
               |> Ash.run_action()

      assert existing_id == existing.id
    end

    test "different date_tokens with the same slug + drawer do NOT collide",
         %{user: user, seed_card: seed_card} do
      _existing = seed_card.("THERMOPYLAE", :event)

      assert {:ok, %{status: :resolved, call_number: cn, existing_card_id: nil}} =
               Manillum.Archive.Card
               |> Ash.ActionInput.for_action(:propose_call_number, %{
                 user_id: user.id,
                 drawer: :ANT,
                 # different date_token from the seeded "1177BC"
                 date_token: "480BC",
                 slug: "THERMOPYLAE",
                 card_type: :event
               })
               |> Ash.run_action()

      assert cn == "ANT · 480BC · THERMOPYLAE"
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

  describe ":file action" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "file_test@example.com"})

      seed = fn slug, status ->
        Ash.Seed.seed!(Card, %{
          user_id: user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: slug,
          card_type: :event,
          front: "F",
          back: "B",
          status: status
        })
      end

      {:ok, user: user, seed: seed}
    end

    test "transitions a :draft card to :filed", %{seed: seed} do
      card = seed.("DRAFT-CARD", :draft)

      assert {:ok, filed} =
               card
               |> Ash.Changeset.for_update(:file, %{})
               |> Ash.update()

      assert filed.status == :filed
    end

    test "rejects filing an already-filed card", %{seed: seed} do
      card = seed.("FILED-CARD", :filed)

      assert {:error, _} =
               card
               |> Ash.Changeset.for_update(:file, %{})
               |> Ash.update()
    end

    test "rejects filing an archived card", %{seed: seed} do
      card = seed.("ARCH-CARD", :archived)

      assert {:error, _} =
               card
               |> Ash.Changeset.for_update(:file, %{})
               |> Ash.update()
    end
  end

  describe ":unfile action" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "unfile_test@example.com"})

      seed = fn slug, status ->
        Ash.Seed.seed!(Card, %{
          user_id: user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: slug,
          card_type: :event,
          front: "F",
          back: "B",
          status: status
        })
      end

      {:ok, user: user, seed: seed}
    end

    test "transitions a :filed card back to :draft", %{seed: seed} do
      card = seed.("FILED-UNDO", :filed)

      assert {:ok, drafted} =
               card
               |> Ash.Changeset.for_update(:unfile, %{})
               |> Ash.update()

      assert drafted.status == :draft
    end

    test "rejects unfiling a :draft card", %{seed: seed} do
      card = seed.("DRAFT-UNDO", :draft)

      assert {:error, _} =
               card
               |> Ash.Changeset.for_update(:unfile, %{})
               |> Ash.update()
    end

    test "rejects unfiling an archived card", %{seed: seed} do
      card = seed.("ARCH-UNDO", :archived)

      assert {:error, _} =
               card
               |> Ash.Changeset.for_update(:unfile, %{})
               |> Ash.update()
    end
  end

  describe ":discard action" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "discard_test@example.com"})

      seed = fn slug, status ->
        Ash.Seed.seed!(Card, %{
          user_id: user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: slug,
          card_type: :event,
          front: "F",
          back: "B",
          status: status
        })
      end

      {:ok, user: user, seed: seed}
    end

    test "destroys a :draft card", %{seed: seed} do
      card = seed.("DRAFT-DISCARD", :draft)

      assert :ok =
               card
               |> Ash.Changeset.for_destroy(:discard, %{})
               |> Ash.destroy()

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(Card, card.id, authorize?: false)
    end

    test "rejects discarding a filed card", %{seed: seed} do
      card = seed.("FILED-DISCARD", :filed)

      assert {:error, _} =
               card
               |> Ash.Changeset.for_destroy(:discard, %{})
               |> Ash.destroy()
    end
  end

  describe ":my_drafts action" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "drafts_list@example.com"})
      other = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "drafts_other@example.com"})

      seed = fn user_id, slug, status ->
        Ash.Seed.seed!(Card, %{
          user_id: user_id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: slug,
          card_type: :event,
          front: "F",
          back: "B",
          status: status
        })
      end

      {:ok, user: user, other: other, seed: seed}
    end

    test "returns only the actor's :draft cards", %{user: user, other: other, seed: seed} do
      d1 = seed.(user.id, "ALPHA", :draft)
      _filed = seed.(user.id, "BETA", :filed)
      _other = seed.(other.id, "GAMMA", :draft)

      assert {:ok, [loaded]} = Manillum.Archive.list_drafts(actor: user)
      assert loaded.id == d1.id
      assert loaded.status == :draft
    end

    test "loads call_number and capture", %{user: user, seed: seed} do
      _ = seed.(user.id, "DELTA", :draft)

      assert {:ok, [loaded]} = Manillum.Archive.list_drafts(actor: user)
      assert loaded.call_number == "ANT · 1177BC · DELTA"
      # capture is a belongs_to; nil here because the seed didn't set capture_id
      assert Map.has_key?(loaded, :capture)
    end
  end
end
