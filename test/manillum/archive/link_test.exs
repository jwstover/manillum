defmodule Manillum.Archive.LinkTest do
  use Manillum.DataCase, async: false

  alias Manillum.Archive
  alias Manillum.Archive.Card
  alias Manillum.Archive.Link

  require Ash.Query

  defp make_user(email) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{email: email})
  end

  defp seed_card(user, slug, opts \\ []) do
    Ash.Seed.seed!(
      Card,
      Map.merge(
        %{
          user_id: user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: slug,
          card_type: :event,
          front: "F",
          back: "B"
        },
        Enum.into(opts, %{})
      )
    )
  end

  describe "resource shape" do
    test "is registered on Manillum.Archive" do
      assert Link in Ash.Domain.Info.resources(Manillum.Archive)
    end

    test "has §4 attributes" do
      attrs = Link |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

      for name <- [:id, :kind, :inserted_at, :updated_at] do
        assert name in attrs, "expected attribute #{inspect(name)} on Link"
      end
    end

    test "has unique_directed_link identity on (from_card_id, to_card_id, kind)" do
      identity =
        Link
        |> Ash.Resource.Info.identities()
        |> Enum.find(&(&1.name == :unique_directed_link))

      assert identity, "expected :unique_directed_link identity"
      assert identity.keys == [:from_card_id, :to_card_id, :kind]
    end

    test "kind enum constraints match §4" do
      attr = Ash.Resource.Info.attribute(Link, :kind)

      assert Keyword.get(attr.constraints, :one_of) == [:see_also, :derived_from, :references]
    end
  end

  describe ":link action" do
    setup do
      user = make_user("link_test@example.com")
      from_card = seed_card(user, "FROM-CARD")
      to_card = seed_card(user, "TO-CARD")
      {:ok, user: user, from: from_card, to: to_card}
    end

    test "creates a directed edge with the requested kind", %{from: from, to: to} do
      assert {:ok, link} =
               Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :see_also})

      assert link.from_card_id == from.id
      assert link.to_card_id == to.id
      assert link.kind == :see_also
    end

    test "is idempotent on the same (from, to, kind) triple", %{from: from, to: to} do
      assert {:ok, _} = Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :see_also})
      assert {:ok, _} = Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :see_also})

      links =
        Link
        |> Ash.Query.filter(from_card_id == ^from.id and to_card_id == ^to.id)
        |> Ash.read!(authorize?: false)

      assert length(links) == 1
    end

    test "different kinds between the same pair coexist", %{from: from, to: to} do
      assert {:ok, l1} =
               Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :see_also})

      assert {:ok, l2} =
               Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :references})

      refute l1.id == l2.id
    end

    test "directed: A→B does not imply B→A", %{from: from, to: to} do
      assert {:ok, _} = Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :see_also})

      reverse =
        Link
        |> Ash.Query.filter(from_card_id == ^to.id and to_card_id == ^from.id)
        |> Ash.read!(authorize?: false)

      assert reverse == []
    end

    test "rejects self-links", %{from: from} do
      assert {:error, %Ash.Error.Invalid{}} =
               Archive.link(%{from_card_id: from.id, to_card_id: from.id, kind: :see_also})
    end

    test "rejects cross-user links" do
      alice = make_user("link_alice@example.com")
      bob = make_user("link_bob@example.com")
      alice_card = seed_card(alice, "ALICE-CARD")
      bob_card = seed_card(bob, "BOB-CARD")

      assert {:error, %Ash.Error.Invalid{}} =
               Archive.link(%{
                 from_card_id: alice_card.id,
                 to_card_id: bob_card.id,
                 kind: :see_also
               })
    end

    test "outgoing_links / incoming_links navigate the edge from each side",
         %{from: from, to: to} do
      assert {:ok, _} = Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :see_also})

      from_loaded = Ash.load!(from, [:outgoing_links, :incoming_links])
      to_loaded = Ash.load!(to, [:outgoing_links, :incoming_links])

      assert [%Link{kind: :see_also, to_card_id: to_id}] = from_loaded.outgoing_links
      assert to_id == to.id
      assert from_loaded.incoming_links == []

      assert to_loaded.outgoing_links == []
      assert [%Link{kind: :see_also, from_card_id: from_id}] = to_loaded.incoming_links
      assert from_id == from.id
    end
  end

  describe ":unlink action" do
    setup do
      user = make_user("unlink_test@example.com")
      from = seed_card(user, "U-FROM")
      to = seed_card(user, "U-TO")

      {:ok, link} = Archive.link(%{from_card_id: from.id, to_card_id: to.id, kind: :see_also})
      {:ok, link: link, from: from, to: to}
    end

    test "removes the link", %{link: link, from: from, to: to} do
      assert :ok = Archive.unlink(link)

      links =
        Link
        |> Ash.Query.filter(from_card_id == ^from.id and to_card_id == ^to.id)
        |> Ash.read!(authorize?: false)

      assert links == []
    end
  end

  describe "kind-specific filtering" do
    setup do
      user = make_user("link_filter@example.com")
      a = seed_card(user, "FILTER-A")
      b = seed_card(user, "FILTER-B")

      {:ok, _} = Archive.link(%{from_card_id: a.id, to_card_id: b.id, kind: :see_also})
      {:ok, _} = Archive.link(%{from_card_id: a.id, to_card_id: b.id, kind: :derived_from})

      {:ok, a: a, b: b}
    end

    test "filtering by kind returns only matching edges", %{a: a, b: b} do
      see_also_only =
        Link
        |> Ash.Query.filter(from_card_id == ^a.id and to_card_id == ^b.id and kind == :see_also)
        |> Ash.read!(authorize?: false)

      assert [%Link{kind: :see_also}] = see_also_only
    end
  end
end
