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

    test "has unique_segments identity on (user_id, drawer, date_token, slug)" do
      identity =
        Card |> Ash.Resource.Info.identities() |> Enum.find(&(&1.name == :unique_segments))

      assert identity, "expected :unique_segments identity"
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
end
