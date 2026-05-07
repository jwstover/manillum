defmodule Manillum.Conversations.MyConversationsTest do
  use Manillum.DataCase, async: false

  alias Manillum.Conversations
  alias Manillum.Conversations.Conversation

  describe ":my_conversations action" do
    setup do
      user = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "my_convs@example.com"})
      other = Ash.Seed.seed!(Manillum.Accounts.User, %{email: "my_convs_other@example.com"})

      {:ok, user: user, other: other}
    end

    test "returns the actor's conversations sorted by updated_at DESC", %{user: user} do
      older =
        Ash.Seed.seed!(Conversation, %{
          user_id: user.id,
          query_number: 1,
          title: "older",
          inserted_at: ~U[2026-01-01 00:00:00Z],
          updated_at: ~U[2026-01-01 00:00:00Z]
        })

      newer =
        Ash.Seed.seed!(Conversation, %{
          user_id: user.id,
          query_number: 2,
          title: "newer",
          inserted_at: ~U[2026-02-01 00:00:00Z],
          updated_at: ~U[2026-02-01 00:00:00Z]
        })

      assert [first, second] = Conversations.my_conversations!(actor: user)
      assert first.id == newer.id
      assert second.id == older.id
    end

    test "scopes to the actor", %{user: user, other: other} do
      _mine =
        Ash.Seed.seed!(Conversation, %{user_id: user.id, query_number: 1, title: "mine"})

      _theirs =
        Ash.Seed.seed!(Conversation, %{user_id: other.id, query_number: 1, title: "theirs"})

      mine = Conversations.my_conversations!(actor: user)
      theirs = Conversations.my_conversations!(actor: other)

      assert length(mine) == 1
      assert length(theirs) == 1
      assert hd(mine).title == "mine"
      assert hd(theirs).title == "theirs"
    end
  end
end
