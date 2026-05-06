defmodule ManillumWeb.ConversationsLiveTest do
  use ManillumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Manillum.Conversations.Mention

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

  defp place_event(user, conversation, message, attrs) do
    Mention
    |> Ash.Changeset.for_create(:place_event_on_timeline, attrs,
      actor: user,
      context: %{
        current_conversation_id: conversation.id,
        current_message_id: message.id
      }
    )
    |> Ash.create!()
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user_with_token = %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user_with_token)
  end

  describe "mention markers on the era band" do
    setup ctx do
      user = make_user("conversations_live_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)

      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation, message: message}
    end

    test "renders pre-existing mentions when navigating to a conversation", ctx do
      _hastings =
        place_event(ctx.user, ctx.conversation, ctx.message, %{
          title: "Battle of Hastings",
          summary: "William defeats Harold.",
          year: 1066,
          month: 10,
          day: 14
        })

      _caesar =
        place_event(ctx.user, ctx.conversation, ctx.message, %{
          title: "Assassination of Caesar",
          summary: "Ides of March.",
          year: -44,
          month: 3,
          day: 15
        })

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      # Two marks rendered on the band
      marks = Regex.scan(~r/class="era_band__event"/, html)
      assert length(marks) == 2

      # Tooltip content matches — header splits year + AD/BC + era;
      # subtitle carries day+month
      assert html =~ "Battle of Hastings"
      assert html =~ "1066"
      assert html =~ "AD · MIDDLE AGES"
      assert html =~ "14 October"

      assert html =~ "Assassination of Caesar"
      assert html =~ "BC · CLASSICAL"
      assert html =~ "15 March"
    end

    test "renders no marks when the conversation has no mentions yet", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      refute html =~ "era_band__event"
    end

    test "broadcasts a :mention_placed payload that re-renders into the band", ctx do
      {:ok, view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")
      refute html =~ "era_band__event"

      _hastings =
        place_event(ctx.user, ctx.conversation, ctx.message, %{
          title: "Battle of Hastings",
          summary: "William defeats Harold.",
          year: 1066,
          month: 10,
          day: 14
        })

      html = render(view)
      assert html =~ "era_band__event"
      assert html =~ "Battle of Hastings"
      assert html =~ "14 October"
    end

    test "scopes mentions to the active conversation", ctx do
      other_conversation = make_conversation(ctx.user, 2)
      other_message = make_message(other_conversation)

      _on_other =
        place_event(ctx.user, other_conversation, other_message, %{
          title: "Apollo 11",
          year: 1969
        })

      _on_active =
        place_event(ctx.user, ctx.conversation, ctx.message, %{
          title: "Battle of Hastings",
          year: 1066
        })

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      assert html =~ "Battle of Hastings"
      refute html =~ "Apollo 11"
    end
  end
end
