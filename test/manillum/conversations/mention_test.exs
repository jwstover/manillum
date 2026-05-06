defmodule Manillum.Conversations.MentionTest do
  use Manillum.DataCase, async: true

  alias Manillum.Conversations
  alias Manillum.Conversations.Mention

  require Ash.Query

  defp make_user(email) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{email: email})
  end

  defp make_conversation(user, query_number \\ 1) do
    Ash.Seed.seed!(Manillum.Conversations.Conversation, %{
      user_id: user.id,
      query_number: query_number,
      title: "Test conversation"
    })
  end

  defp make_message(conversation, role \\ :assistant, content \\ "Hello") do
    Ash.Seed.seed!(Manillum.Conversations.Message, %{
      conversation_id: conversation.id,
      role: role,
      content: content,
      complete: true
    })
  end

  defp create_mention(user, conversation, message, attrs \\ %{}) do
    base = %{
      title: "Battle of Hastings",
      summary: "William defeats Harold.",
      year: 1066,
      month: 10,
      day: 14
    }

    Mention
    |> Ash.Changeset.for_create(:create, Map.merge(base, attrs),
      actor: user,
      private_arguments: %{
        conversation_id: conversation.id,
        message_id: message.id
      }
    )
    |> Ash.create()
  end

  defp place_event(user, conversation, message, attrs \\ %{}) do
    base = %{
      title: "Battle of Hastings",
      summary: "William defeats Harold.",
      year: 1066,
      month: 10,
      day: 14
    }

    Mention
    |> Ash.Changeset.for_create(:place_event_on_timeline, Map.merge(base, attrs),
      actor: user,
      context: %{
        current_conversation_id: conversation.id,
        current_message_id: message.id
      }
    )
    |> Ash.create()
  end

  describe "resource shape" do
    test "is registered on Manillum.Conversations" do
      assert Mention in Ash.Domain.Info.resources(Conversations)
    end

    test "has the §M-41 attributes" do
      attrs = Mention |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

      for name <- [
            :id,
            :title,
            :normalized_title,
            :summary,
            :year,
            :month,
            :day,
            :mentioned_at,
            :inserted_at,
            :updated_at,
            :user_id,
            :conversation_id,
            :message_id
          ] do
        assert name in attrs, "expected attribute #{inspect(name)} on Mention"
      end
    end

    test "exposes the unique identity (user, conversation, year, normalized_title)" do
      [identity] = Ash.Resource.Info.identities(Mention)

      assert identity.name == :unique_per_conversation_year_title
      assert identity.keys == [:user_id, :conversation_id, :year, :normalized_title]
    end
  end

  describe ":create action" do
    setup do
      user = make_user("mention_create@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)
      {:ok, user: user, conversation: conversation, message: message}
    end

    test "writes a row with the supplied fields", ctx do
      assert {:ok, mention} = create_mention(ctx.user, ctx.conversation, ctx.message)

      assert mention.title == "Battle of Hastings"
      assert mention.year == 1066
      assert mention.month == 10
      assert mention.day == 14
      assert mention.user_id == ctx.user.id
      assert mention.conversation_id == ctx.conversation.id
      assert mention.message_id == ctx.message.id
    end

    test "auto-sets normalized_title to lowercased + trimmed title", ctx do
      assert {:ok, mention} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{
                 title: "  Battle of Hastings  "
               })

      assert mention.normalized_title == "battle of hastings"
    end

    test "auto-sets mentioned_at when not provided", ctx do
      before_call = DateTime.utc_now() |> DateTime.add(-1, :second)
      assert {:ok, mention} = create_mention(ctx.user, ctx.conversation, ctx.message)
      after_call = DateTime.utc_now() |> DateTime.add(1, :second)

      assert DateTime.compare(mention.mentioned_at, before_call) in [:gt, :eq]
      assert DateTime.compare(mention.mentioned_at, after_call) in [:lt, :eq]
    end

    test "accepts a year-only mention (month/day nil)", ctx do
      assert {:ok, mention} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{
                 month: nil,
                 day: nil
               })

      assert mention.year == 1066
      assert mention.month == nil
      assert mention.day == nil
    end

    test "accepts a month-only mention (day nil)", ctx do
      assert {:ok, mention} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{
                 day: nil
               })

      assert mention.month == 10
      assert mention.day == nil
    end

    test "accepts a BC year (negative integer)", ctx do
      assert {:ok, mention} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{
                 title: "Assassination of Caesar",
                 year: -44,
                 month: 3,
                 day: 15
               })

      assert mention.year == -44
      assert mention.month == 3
      assert mention.day == 15
    end
  end

  describe "validations" do
    setup do
      user = make_user("mention_validate@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)
      {:ok, user: user, conversation: conversation, message: message}
    end

    test "rejects month outside 1..12", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{month: 13, day: nil})

      assert {:error, %Ash.Error.Invalid{}} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{month: 0, day: nil})
    end

    test "rejects day outside 1..31", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{day: 32})

      assert {:error, %Ash.Error.Invalid{}} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{day: 0})
    end

    test "rejects day-without-month (meaningless)", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{
                 month: nil,
                 day: 14
               })
    end
  end

  describe "identity uniqueness" do
    setup do
      user = make_user("mention_dedup@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)
      {:ok, user: user, conversation: conversation, message: message}
    end

    test "rejects a duplicate (user, conversation, year, normalized_title)", ctx do
      assert {:ok, _} = create_mention(ctx.user, ctx.conversation, ctx.message)

      assert {:error, %Ash.Error.Invalid{}} =
               create_mention(ctx.user, ctx.conversation, ctx.message)
    end

    test "normalizes title for dedup (case + whitespace differences are equivalent)", ctx do
      assert {:ok, _} = create_mention(ctx.user, ctx.conversation, ctx.message)

      assert {:error, %Ash.Error.Invalid{}} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{
                 title: "  BATTLE OF HASTINGS  "
               })
    end

    test "different year with same title is allowed (events repeat across years)", ctx do
      assert {:ok, _} = create_mention(ctx.user, ctx.conversation, ctx.message)

      assert {:ok, _} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{year: 1067})
    end

    test "same mention in a different conversation is allowed", ctx do
      other_conversation = make_conversation(ctx.user, 2)
      other_message = make_message(other_conversation)

      assert {:ok, _} = create_mention(ctx.user, ctx.conversation, ctx.message)
      assert {:ok, _} = create_mention(ctx.user, other_conversation, other_message)
    end
  end

  describe ":place_event_on_timeline tool action" do
    setup do
      user = make_user("mention_tool@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)
      {:ok, user: user, conversation: conversation, message: message}
    end

    test "writes the row using conversation/message ids from action context", ctx do
      assert {:ok, mention} = place_event(ctx.user, ctx.conversation, ctx.message)

      assert mention.title == "Battle of Hastings"
      assert mention.year == 1066
      assert mention.user_id == ctx.user.id
      assert mention.conversation_id == ctx.conversation.id
      assert mention.message_id == ctx.message.id
    end

    test "tool action does not accept conversation_id / message_id from input", _ctx do
      action_inputs =
        Mention
        |> Ash.Resource.Info.action(:place_event_on_timeline)
        |> Map.get(:accept)

      refute :conversation_id in action_inputs
      refute :message_id in action_inputs
    end

    test "errors when invoked without the tool-loop context", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Mention
               |> Ash.Changeset.for_create(
                 :place_event_on_timeline,
                 %{
                   title: "Battle of Hastings",
                   summary: "—",
                   year: 1066
                 },
                 actor: ctx.user
               )
               |> Ash.create()
    end

    test "is idempotent on (user, conversation, year, normalized_title)", ctx do
      assert {:ok, first} = place_event(ctx.user, ctx.conversation, ctx.message)

      # Second call with the same identifying fields — would error on the
      # plain `:create` action (covered above) but the upsert variant
      # returns the existing row without raising.
      assert {:ok, second} = place_event(ctx.user, ctx.conversation, ctx.message)

      assert first.id == second.id
    end

    test "case + whitespace differences in title still hit the upsert", ctx do
      assert {:ok, first} = place_event(ctx.user, ctx.conversation, ctx.message)

      assert {:ok, second} =
               place_event(ctx.user, ctx.conversation, ctx.message, %{
                 title: "  BATTLE OF HASTINGS  "
               })

      assert first.id == second.id
    end

    test "different year with same title creates a separate row", ctx do
      assert {:ok, first} = place_event(ctx.user, ctx.conversation, ctx.message)

      assert {:ok, second} =
               place_event(ctx.user, ctx.conversation, ctx.message, %{year: 1067})

      assert first.id != second.id
    end

    test "is registered as a tool on the Conversations domain", _ctx do
      tools = AshAi.Info.tools(Manillum.Conversations)
      tool_names = Enum.map(tools, & &1.name)

      assert :place_event_on_timeline in tool_names

      tool = Enum.find(tools, &(&1.name == :place_event_on_timeline))
      assert tool.resource == Mention
      assert tool.action == :place_event_on_timeline
    end
  end

  describe "PubSub broadcast" do
    setup do
      user = make_user("mention_pubsub@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)
      {:ok, user: user, conversation: conversation, message: message}
    end

    test "publishes :mention_placed shape on chat:messages:<conversation_id>", ctx do
      ManillumWeb.Endpoint.subscribe("chat:messages:#{ctx.conversation.id}")

      assert {:ok, mention} =
               create_mention(ctx.user, ctx.conversation, ctx.message, %{
                 title: "Battle of Hastings",
                 year: 1066,
                 month: 10,
                 day: 14,
                 summary: "William defeats Harold."
               })

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: topic,
                       payload: %{
                         kind: :mention_placed,
                         id: id,
                         title: "Battle of Hastings",
                         year: 1066,
                         month: 10,
                         day: 14,
                         summary: "William defeats Harold.",
                         message_id: message_id
                       }
                     },
                     500

      assert topic == "chat:messages:#{ctx.conversation.id}"
      assert id == mention.id
      assert message_id == ctx.message.id
    end
  end

  describe ":for_conversation read action" do
    setup do
      user = make_user("mention_list@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)
      {:ok, user: user, conversation: conversation, message: message}
    end

    test "lists this conversation's mentions sorted chronologically", ctx do
      {:ok, _} =
        create_mention(ctx.user, ctx.conversation, ctx.message, %{
          title: "Battle of Hastings",
          year: 1066
        })

      {:ok, _} =
        create_mention(ctx.user, ctx.conversation, ctx.message, %{
          title: "Fall of Rome",
          year: 476
        })

      {:ok, _} =
        create_mention(ctx.user, ctx.conversation, ctx.message, %{
          title: "Caesar assassinated",
          year: -44,
          month: 3,
          day: 15
        })

      mentions = Conversations.list_mentions!(ctx.conversation.id, actor: ctx.user)

      assert Enum.map(mentions, & &1.year) == [-44, 476, 1066]
    end

    test "scopes to actor's user_id", ctx do
      other_user = make_user("mention_list_other@example.com")
      other_conversation = make_conversation(other_user)
      other_message = make_message(other_conversation)

      {:ok, _} = create_mention(ctx.user, ctx.conversation, ctx.message)
      {:ok, _} = create_mention(other_user, other_conversation, other_message)

      assert [mention] = Conversations.list_mentions!(ctx.conversation.id, actor: ctx.user)
      assert mention.user_id == ctx.user.id

      assert Conversations.list_mentions!(other_conversation.id, actor: ctx.user) == []
    end
  end
end
