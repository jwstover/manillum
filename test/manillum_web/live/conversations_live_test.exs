defmodule ManillumWeb.ConversationsLiveTest do
  use ManillumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Manillum.Archive
  alias Manillum.Archive.Capture
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

  describe "+ FILE ALL affordance (rendered)" do
    setup ctx do
      user = make_user("file_all_render_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation}
    end

    test "renders + FILE ALL on a complete assistant message", ctx do
      _msg = make_message(ctx.conversation, :assistant, "Livy: full reply.")

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      assert html =~ "+ FILE ALL"
      assert html =~ "message__file_all_btn"
    end

    test "does not render + FILE ALL on user messages", ctx do
      _msg = make_message(ctx.conversation, :user, "what was the date of cannae?")

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      refute html =~ "+ FILE ALL"
    end

    test "does not render + FILE ALL on incomplete assistant messages", ctx do
      _streaming =
        Ash.Seed.seed!(Manillum.Conversations.Message, %{
          conversation_id: ctx.conversation.id,
          role: :assistant,
          content: "still streaming…",
          complete: false
        })

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      refute html =~ "+ FILE ALL"
    end
  end

  describe "file event — :whole scope" do
    setup ctx do
      user = make_user("file_whole_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation, :assistant, "Cannae fell on August 2, 216 BC.")
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation, message: message}
    end

    test "clicking + FILE ALL submits a Capture with scope=:whole and the message body", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      html =
        view
        |> element("button.message__file_all_btn")
        |> render_click()

      assert html =~ "Filing — drafts will appear shortly"

      [capture] = list_captures(ctx.user)
      assert capture.scope == :whole
      assert capture.status == :pending
      assert capture.source_text == ctx.message.content
      assert capture.user_id == ctx.user.id
      assert capture.conversation_id == ctx.conversation.id
      assert capture.message_id == ctx.message.id
    end
  end

  describe "file event — :selection scope" do
    setup ctx do
      user = make_user("file_selection_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation, :assistant, "Cannae fell on August 2, 216 BC.")
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation, message: message}
    end

    test "selection push event submits a Capture with the selected text", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      html =
        render_hook(view, "file", %{
          "scope" => "selection",
          "message_id" => ctx.message.id,
          "conversation_id" => ctx.conversation.id,
          "text" => "August 2, 216 BC"
        })

      assert html =~ "Filing — drafts will appear shortly"

      [capture] = list_captures(ctx.user)
      assert capture.scope == :selection
      assert capture.source_text == "August 2, 216 BC"
      assert capture.message_id == ctx.message.id
    end

    test "rejects empty selection text with a flash", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      html =
        render_hook(view, "file", %{
          "scope" => "selection",
          "message_id" => ctx.message.id,
          "conversation_id" => ctx.conversation.id,
          "text" => "   "
        })

      assert html =~ "Couldn&#39;t file: empty selection"
      assert list_captures(ctx.user) == []
    end
  end

  describe "file event — guards" do
    setup ctx do
      user = make_user("file_guards_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      message = make_message(conversation)
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation, message: message}
    end

    test "missing message_id flashes an error and persists nothing", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      html =
        render_hook(view, "file", %{
          "scope" => "whole",
          "conversation_id" => ctx.conversation.id
        })

      assert html =~ "Couldn&#39;t file: missing message_id"
      assert list_captures(ctx.user) == []
    end

    test "missing scope flashes an error", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      html =
        render_hook(view, "file", %{
          "message_id" => ctx.message.id,
          "conversation_id" => ctx.conversation.id
        })

      assert html =~ "Couldn&#39;t file: missing scope"
    end
  end

  describe "filing tray (Slice 10A / M-28)" do
    setup ctx do
      user = make_user("filing_tray_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      _message = make_message(conversation)
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation}
    end

    test "the tray container collapses when the user has no drafts", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")
      html = render(view)

      # Tray markup stays in the DOM so Phoenix LV streams keep their
      # items across show/hide; CSS handles the collapse.
      assert html =~ "filing_tray__container--empty"
      refute html =~ "filing_tray__reopen"
    end

    test "loads existing drafts on mount", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      _draft = seed_draft(ctx.user, capture, "ALPHA")
      _draft = seed_draft(ctx.user, capture, "BETA")

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      assert html =~ "FILING TRAY · 2 DRAFTS"
      assert html =~ "ANT · 1177BC · ALPHA"
      assert html =~ "ANT · 1177BC · BETA"
    end

    test ":cards_drafted broadcast appends new drafts", ctx do
      {:ok, view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")
      assert html =~ "filing_tray__container--empty"

      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "GAMMA")

      Phoenix.PubSub.broadcast(
        Manillum.PubSub,
        "user:#{ctx.user.id}:cataloging",
        {:cards_drafted,
         %{
           capture_id: capture.id,
           conversation_id: ctx.conversation.id,
           draft_ids: [draft.id]
         }}
      )

      html = render(view)
      assert html =~ "FILING TRAY · 1 DRAFT"
      assert html =~ "ANT · 1177BC · GAMMA"
    end

    test ":cards_drafting_failed broadcast surfaces a banner", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      Phoenix.PubSub.broadcast(
        Manillum.PubSub,
        "user:#{ctx.user.id}:cataloging",
        {:cards_drafting_failed, %{capture_id: Ecto.UUID.generate(), reason: "LLM timeout"}}
      )

      # Force a sync barrier so the broadcast → handle_info →
      # send_update → component re-render chain settles before
      # render(view) snapshots the HTML. Without this, the queued
      # send_update message can land behind render(view)'s GenServer
      # call and the assertion sees the pre-broadcast state.
      _ = :sys.get_state(view.pid)
      html = render(view)
      assert html =~ "Cataloging failed"
      assert html =~ "LLM timeout"
    end

    test "close hides the tray and surfaces a spine; reopen brings drafts back", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      _draft = seed_draft(ctx.user, capture, "EPSILON")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element(".filing_tray__close")
      |> render_click()

      html = render(view)
      assert html =~ "filing_tray__container--dismissed"
      assert html =~ "Reopen filing tray"
      assert html =~ "Filing tray · 1 · show"

      view
      |> element(".filing_tray__spine")
      |> render_click()

      html = render(view)
      refute html =~ "filing_tray__container--dismissed"
      assert html =~ "ANT · 1177BC · EPSILON"
    end

    test "broadcast while dismissed bumps the count without forcing the tray open", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      first = seed_draft(ctx.user, capture, "ZETA")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view |> element(".filing_tray__close") |> render_click()
      assert render(view) =~ "Filing tray · 1 · show"

      second = seed_draft(ctx.user, capture, "ETA")

      Phoenix.PubSub.broadcast(
        Manillum.PubSub,
        "user:#{ctx.user.id}:cataloging",
        {:cards_drafted,
         %{
           capture_id: capture.id,
           conversation_id: ctx.conversation.id,
           draft_ids: [second.id]
         }}
      )

      _ = :sys.get_state(view.pid)
      html = render(view)
      assert html =~ "filing_tray__container--dismissed"
      assert html =~ "Filing tray · 2 · show"
      _ = first
    end

    test "discard removes the draft from the tray and the DB", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "DELTA")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("article[id*='#{draft.id}'] button[phx-click='discard']")
      |> render_click()

      html = render(view)
      refute html =~ "ANT · 1177BC · DELTA"
      assert html =~ "filing_tray__container--empty"

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(Manillum.Archive.Card, draft.id, authorize?: false)
    end
  end

  defp seed_capture(user, conversation) do
    Ash.Seed.seed!(Capture, %{
      user_id: user.id,
      source_text: "seed source",
      scope: :whole,
      status: :catalogued,
      conversation_id: conversation.id,
      message_id: Ecto.UUID.generate()
    })
  end

  defp seed_draft(user, capture, slug) do
    Ash.Seed.seed!(Manillum.Archive.Card, %{
      user_id: user.id,
      capture_id: capture.id,
      drawer: :ANT,
      date_token: "1177BC",
      slug: slug,
      card_type: :event,
      front: "front for #{slug}",
      back: "back for #{slug}",
      status: :draft
    })
  end

  defp list_captures(user) do
    Capture
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read!(domain: Archive, authorize?: false)
  end
end
