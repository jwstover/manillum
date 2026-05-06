defmodule Manillum.Archive.RenameTest do
  use Manillum.DataCase, async: false

  alias Manillum.Archive
  alias Manillum.Archive.CallNumberRedirect
  alias Manillum.Archive.Card

  require Ash.Query

  defp make_user(email) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{email: email})
  end

  defp seed_card(user, opts) do
    base = %{
      user_id: user.id,
      drawer: :ANT,
      date_token: "49BC",
      slug: "CAESAR",
      card_type: :person,
      front: "Who was Caesar?",
      back: "A Roman general."
    }

    Ash.Seed.seed!(Card, Enum.into(opts, base))
  end

  describe "CallNumberRedirect resource shape" do
    test "is registered on Manillum.Archive" do
      assert CallNumberRedirect in Ash.Domain.Info.resources(Archive)
    end

    test "has identity on (user_id, drawer, date_token, slug)" do
      identity =
        CallNumberRedirect
        |> Ash.Resource.Info.identities()
        |> Enum.find(&(&1.name == :unique_old_call_number))

      assert identity, "expected :unique_old_call_number identity"
      assert identity.keys == [:user_id, :drawer, :date_token, :slug]
    end
  end

  describe "Card.:rename action" do
    setup do
      user = make_user("rename@example.com")
      Phoenix.PubSub.subscribe(Manillum.PubSub, "user:#{user.id}:archive")
      {:ok, user: user}
    end

    test "updates segments and writes a CallNumberRedirect for the old segments",
         %{user: user} do
      card = seed_card(user, [])
      old_call_number = "ANT · 49BC · CAESAR"

      assert {:ok, renamed} = Archive.rename_card(card, %{slug: "JULIUS-CAESAR"})

      assert renamed.slug == "JULIUS-CAESAR"

      [redirect] =
        CallNumberRedirect
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.read!(authorize?: false)

      assert redirect.drawer == :ANT
      assert redirect.date_token == "49BC"
      assert redirect.slug == "CAESAR"
      assert redirect.current_card_id == card.id

      new_call_number = "ANT · 49BC · JULIUS-CAESAR"
      assert_receive {:card_renamed, ^old_call_number, ^new_call_number}, 500
    end

    test "rejects renaming onto an existing identity", %{user: user} do
      # The `:unique_call_number` identity is partial (`status != :draft`),
      # so the collision is enforced between filed cards. Use :filed so
      # the constraint actually fires.
      _existing = seed_card(user, slug: "OCTAVIAN", status: :filed)
      caesar = seed_card(user, status: :filed)

      assert {:error, _} = Archive.rename_card(caesar, %{slug: "OCTAVIAN"})
    end

    test "no-op rename (same segments) does not write a redirect but still broadcasts",
         %{user: user} do
      card = seed_card(user, [])
      same_call_number = "ANT · 49BC · CAESAR"

      assert {:ok, _} = Archive.rename_card(card, %{slug: "CAESAR"})

      redirects =
        CallNumberRedirect
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.read!(authorize?: false)

      assert redirects == []

      assert_receive {:card_renamed, ^same_call_number, ^same_call_number}, 500
    end

    test "two-hop rename: both old call_numbers resolve to the same card", %{user: user} do
      card = seed_card(user, [])

      {:ok, _} = Archive.rename_card(card, %{slug: "JULIUS-CAESAR"})
      reloaded = Ash.get!(Card, card.id, authorize?: false)
      {:ok, _} = Archive.rename_card(reloaded, %{slug: "DICTATOR-CAESAR"})

      # Two redirects: the original CAESAR pre-rename, and JULIUS-CAESAR
      # from the second rename. Both point at the same card id.
      redirects =
        CallNumberRedirect
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.read!(authorize?: false)

      assert length(redirects) == 2
      assert Enum.all?(redirects, &(&1.current_card_id == card.id))
      assert Enum.map(redirects, & &1.slug) |> Enum.sort() == ["CAESAR", "JULIUS-CAESAR"]
    end
  end

  describe "Archive.get_card_by_call_number/2" do
    setup do
      {:ok, user: make_user("lookup@example.com")}
    end

    test "returns the card when the segments match a live call_number", %{user: user} do
      card = seed_card(user, [])

      assert {:ok, found} =
               Archive.get_card_by_call_number(user.id, "ANT · 49BC · CAESAR")

      assert found.id == card.id
    end

    test "follows a redirect to the renamed card", %{user: user} do
      card = seed_card(user, [])
      {:ok, _} = Archive.rename_card(card, %{slug: "JULIUS-CAESAR"})

      assert {:ok, found} =
               Archive.get_card_by_call_number(user.id, "ANT · 49BC · CAESAR")

      assert found.id == card.id
      assert found.slug == "JULIUS-CAESAR"
    end

    test "follows a redirect through two renames (multi-hop resolves)", %{user: user} do
      card = seed_card(user, [])
      {:ok, _} = Archive.rename_card(card, %{slug: "JULIUS-CAESAR"})
      reloaded = Ash.get!(Card, card.id, authorize?: false)
      {:ok, _} = Archive.rename_card(reloaded, %{slug: "DICTATOR-CAESAR"})

      # Original name still resolves
      assert {:ok, found_via_original} =
               Archive.get_card_by_call_number(user.id, "ANT · 49BC · CAESAR")

      # First-renamed name also resolves
      assert {:ok, found_via_julius} =
               Archive.get_card_by_call_number(user.id, "ANT · 49BC · JULIUS-CAESAR")

      assert found_via_original.id == card.id
      assert found_via_julius.id == card.id
      assert found_via_original.slug == "DICTATOR-CAESAR"
    end

    test "returns :not_found when neither a card nor a redirect matches", %{user: user} do
      assert {:error, :not_found} =
               Archive.get_card_by_call_number(user.id, "ANT · 49BC · UNKNOWN")
    end

    test "returns :invalid_format on a malformed call_number", %{user: user} do
      assert {:error, :invalid_format} =
               Archive.get_card_by_call_number(user.id, "not a call number")

      assert {:error, :invalid_format} =
               Archive.get_card_by_call_number(user.id, "BOGUS · 49BC · CAESAR")
    end

    test "is per-user — another user's card with the same segments isn't returned", %{user: user} do
      _mine = seed_card(user, [])
      other = make_user("other_lookup@example.com")
      _theirs = seed_card(other, [])

      # Lookup for other user's namespace finds their card, not mine.
      assert {:ok, found} =
               Archive.get_card_by_call_number(other.id, "ANT · 49BC · CAESAR")

      assert found.user_id == other.id
    end
  end

  describe "Gate B.2 retroactive rename scenario" do
    test "rename + file new produces a working two-name lookup space" do
      user = make_user("retroactive@example.com")
      Phoenix.PubSub.subscribe(Manillum.PubSub, "user:#{user.id}:archive")

      caesar = seed_card(user, slug: "CAESAR")

      # Reviewer would prompt the user; here we just rename directly.
      {:ok, renamed} = Archive.rename_card(caesar, %{slug: "JULIUS-CAESAR"})
      assert renamed.slug == "JULIUS-CAESAR"

      # File the new card now that CAESAR is freed up.
      {:ok, octavian} =
        Archive.draft_card(%{
          user_id: user.id,
          drawer: :ANT,
          date_token: "49BC",
          slug: "OCTAVIAN",
          card_type: :person,
          front: "Who was Octavian?",
          back: "Caesar's adopted heir, later Augustus."
        })

      # Both resolve via call_number.
      assert {:ok, looked_up_caesar} =
               Archive.get_card_by_call_number(user.id, "ANT · 49BC · CAESAR")

      assert looked_up_caesar.id == caesar.id
      assert looked_up_caesar.slug == "JULIUS-CAESAR"

      assert {:ok, looked_up_octavian} =
               Archive.get_card_by_call_number(user.id, "ANT · 49BC · OCTAVIAN")

      assert looked_up_octavian.id == octavian.id
    end
  end
end
