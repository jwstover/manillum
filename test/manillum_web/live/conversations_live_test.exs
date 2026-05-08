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
      assert html =~ ~s(phx-click="file")
      assert html =~ ~s(phx-value-scope="whole")
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
        |> element(~s(button.action_pill[phx-click="file"][phx-value-scope="whole"]))
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

  describe "file action — Slice 10B / M-28" do
    setup ctx do
      user = make_user("file_action_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      _message = make_message(conversation)
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation}
    end

    test "file flips the card status to :filed and surfaces the undo toast", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "OMEGA")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      send_file_card(view, draft.id)
      _ = :sys.get_state(view.pid)

      filed = Ash.get!(Manillum.Archive.Card, draft.id, authorize?: false)
      assert filed.status == :filed

      html = render(view)
      assert html =~ "id=\"undo-toast\""
      assert html =~ "ANT · 1177BC · OMEGA"
      assert html =~ ~s(phx-click="undo_file")
    end

    test "post-animation send_update removes the filed draft from the tray", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "OMEGA-REM")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")
      assert render(view) =~ "ANT · 1177BC · OMEGA-REM"

      send_file_card(view, draft.id)
      _ = render(view)

      send(view.pid, {:remove_filed_dom, "drafts-#{draft.id}", draft.id})
      # Two syncs: first drains the explicit message (which triggers
      # send_update — itself a self-send); second drains the
      # send_update message so the component's stream_delete actually
      # runs before render snapshots.
      _ = :sys.get_state(view.pid)
      _ = :sys.get_state(view.pid)

      html = render(view)

      # Article is gone from the tray (the undo toast still shows the
      # filed call_number — that's expected, so don't `refute` on the
      # call_number string itself).
      refute html =~ ~s(id="drafts-#{draft.id}")
    end

    test "undo_file flips the card back to :draft and restores it to the tray", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "OMEGA-UNDO")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      send_file_card(view, draft.id)
      send(view.pid, {:remove_filed_dom, "drafts-#{draft.id}", draft.id})
      _ = :sys.get_state(view.pid)

      view |> element("#undo-toast .toast__actions button") |> render_click()
      _ = :sys.get_state(view.pid)

      restored = Ash.get!(Manillum.Archive.Card, draft.id, authorize?: false)
      assert restored.status == :draft

      html = render(view)
      refute html =~ "id=\"undo-toast\""
      assert html =~ "ANT · 1177BC · OMEGA-UNDO"
    end

    test "undo_expire clears the undo toast without changing card status", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "OMEGA-EXP")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      send_file_card(view, draft.id)
      _ = :sys.get_state(view.pid)
      assert render(view) =~ "id=\"undo-toast\""

      send(view.pid, {:undo_expire, draft.id})
      _ = :sys.get_state(view.pid)

      html = render(view)
      refute html =~ "id=\"undo-toast\""

      filed = Ash.get!(Manillum.Archive.Card, draft.id, authorize?: false)
      assert filed.status == :filed
    end

    test "scheduled :remove_filed_dom is a no-op once the card is unfiled", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "OMEGA-RACE")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      send_file_card(view, draft.id)
      _ = :sys.get_state(view.pid)

      view |> element("#undo-toast .toast__actions button") |> render_click()
      _ = :sys.get_state(view.pid)

      # The card is now back to :draft. The 1100ms `:remove_filed_dom`
      # is still in the parent's mailbox (would normally fire after the
      # animation). When it does fire, it must check status and skip
      # removing — otherwise the just-restored draft vanishes.
      send(view.pid, {:remove_filed_dom, "drafts-#{draft.id}", draft.id})
      _ = :sys.get_state(view.pid)
      _ = :sys.get_state(view.pid)

      html = render(view)
      assert html =~ ~s(id="drafts-#{draft.id}")
      assert html =~ "ANT · 1177BC · OMEGA-RACE"
    end

    test "the file pill carries phx-click directives that strip phx-remove", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "OMEGA-DOM")

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      # The file pill must (a) push the file_card event and (b) strip
      # the article's phx-remove so the eventual stream_delete doesn't
      # rewind the article and replay the discard animation on top.
      # JSON-encoded JS commands surface as `remove_attr` / `add_class` /
      # `push` in the rendered phx-click attribute.
      assert html =~ "file_card"
      assert html =~ "remove_attr"
      assert html =~ "filing_tray__draft--filing"

      _ = draft
    end
  end

  describe "slug-collision banner — Slice 10B / M-64" do
    setup ctx do
      user = make_user("collision_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      _message = make_message(conversation)
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation}
    end

    test "renders the brass collision banner when collision_card_id is set", ctx do
      existing =
        Ash.Seed.seed!(Manillum.Archive.Card, %{
          user_id: ctx.user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "EXISTING-CARD",
          card_type: :event,
          front: "F",
          back: "B",
          status: :filed
        })

      capture = seed_capture(ctx.user, ctx.conversation)

      _draft =
        Ash.Seed.seed!(Manillum.Archive.Card, %{
          user_id: ctx.user.id,
          capture_id: capture.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "COLLIDE-DRAFT",
          card_type: :event,
          front: "front for COLLIDE-DRAFT",
          back: "back for COLLIDE-DRAFT",
          status: :draft,
          collision_card_id: existing.id
        })

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      assert html =~ "filing_tray__draft-collision"
      assert html =~ "Looks like your existing card"
      assert html =~ "ANT · 1177BC · EXISTING-CARD"
    end

    test "draft without a collision renders no banner", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      _draft = seed_draft(ctx.user, capture, "CLEAN-DRAFT")

      {:ok, _view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      refute html =~ "filing_tray__draft-collision"
      assert html =~ "ANT · 1177BC · CLEAN-DRAFT"
    end

    test "the file pill is hidden on a colliding draft", ctx do
      existing =
        Ash.Seed.seed!(Manillum.Archive.Card, %{
          user_id: ctx.user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "EXISTING",
          card_type: :event,
          front: "F",
          back: "B",
          status: :filed
        })

      capture = seed_capture(ctx.user, ctx.conversation)

      draft =
        Ash.Seed.seed!(Manillum.Archive.Card, %{
          user_id: ctx.user.id,
          capture_id: capture.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "GATED-DRAFT",
          card_type: :event,
          front: "front for GATED-DRAFT",
          back: "back for GATED-DRAFT",
          status: :draft,
          collision_card_id: existing.id
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      # No file pill rendered inside the colliding draft article
      refute has_element?(
               view,
               "article[id='drafts-#{draft.id}'] .action_pill--primary"
             )

      # Edit slug + discard pills are present in the collision banner
      assert has_element?(
               view,
               "article[id='drafts-#{draft.id}'] .filing_tray__draft-collision-actions button[phx-click='edit_draft']"
             )

      assert has_element?(
               view,
               "article[id='drafts-#{draft.id}'] .filing_tray__draft-collision-actions button[phx-click='discard']"
             )
    end

    test "edit slug from the collision banner opens inline edit", ctx do
      existing =
        Ash.Seed.seed!(Manillum.Archive.Card, %{
          user_id: ctx.user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "EXISTING",
          card_type: :event,
          front: "F",
          back: "B",
          status: :filed
        })

      capture = seed_capture(ctx.user, ctx.conversation)

      draft =
        Ash.Seed.seed!(Manillum.Archive.Card, %{
          user_id: ctx.user.id,
          capture_id: capture.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "OPEN-EDIT",
          card_type: :event,
          front: "F",
          back: "B",
          status: :draft,
          collision_card_id: existing.id
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element(
        "article[id='drafts-#{draft.id}'] .filing_tray__draft-collision-actions button[phx-click='edit_draft']"
      )
      |> render_click()

      html = render(view)
      assert html =~ "filing_tray__edit"
      assert html =~ ~s(name="draft[slug]")
    end
  end

  describe "file all — Slice 10B / M-63" do
    setup ctx do
      user = make_user("file_all_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      _message = make_message(conversation)
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation}
    end

    test "the `file all` pill renders only when the tray is in :review with drafts", ctx do
      # Tray is :empty — no file all pill
      {:ok, view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")
      refute html =~ "file all"

      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "FA-FIRST")

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

      _ = :sys.get_state(view.pid)
      assert render(view) =~ "file all"
    end

    test "file all flips every draft to :filed and surfaces a single batch undo flash", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft1 = seed_draft(ctx.user, capture, "BATCH-A")
      draft2 = seed_draft(ctx.user, capture, "BATCH-B")
      draft3 = seed_draft(ctx.user, capture, "BATCH-C")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("#filing-tray button[phx-click='file_all']")
      |> render_click()

      _ = :sys.get_state(view.pid)

      # All three drafts flipped to :filed
      for d <- [draft1, draft2, draft3] do
        card = Ash.get!(Manillum.Archive.Card, d.id, authorize?: false)
        assert card.status == :filed
      end

      # One undo flash with the batch count
      html = render(view)
      assert html =~ ~s(id="undo-toast")
      assert html =~ "Filed 3 cards"
      assert html =~ ~s(phx-click="undo_file")
    end

    test "undo from a batch flash restores all cards to drafts", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft1 = seed_draft(ctx.user, capture, "BATCH-UNDO-A")
      draft2 = seed_draft(ctx.user, capture, "BATCH-UNDO-B")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("#filing-tray button[phx-click='file_all']")
      |> render_click()

      _ = :sys.get_state(view.pid)

      view |> element("#undo-toast button[phx-click='undo_file']") |> render_click()
      _ = :sys.get_state(view.pid)

      for d <- [draft1, draft2] do
        card = Ash.get!(Manillum.Archive.Card, d.id, authorize?: false)
        assert card.status == :draft
      end

      html = render(view)
      refute html =~ ~s(id="undo-toast")
      # Cards re-rendered in the tray
      assert html =~ "ANT · 1177BC · BATCH-UNDO-A"
      assert html =~ "ANT · 1177BC · BATCH-UNDO-B"
    end

    test "undo_expire_batch clears the toast without changing card status", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft1 = seed_draft(ctx.user, capture, "BATCH-EXP-A")
      draft2 = seed_draft(ctx.user, capture, "BATCH-EXP-B")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("#filing-tray button[phx-click='file_all']")
      |> render_click()

      _ = :sys.get_state(view.pid)
      assert render(view) =~ ~s(id="undo-toast")

      send(view.pid, {:undo_expire_batch, [draft1.id, draft2.id]})
      _ = :sys.get_state(view.pid)

      html = render(view)
      refute html =~ ~s(id="undo-toast")

      # Cards stay :filed
      for d <- [draft1, draft2] do
        card = Ash.get!(Manillum.Archive.Card, d.id, authorize?: false)
        assert card.status == :filed
      end
    end

    test "file all with no drafts is a no-op (no flash, no error)", ctx do
      # No drafts seeded. The tray is :empty on mount, so the file_all
      # button is hidden via the `:if` guard on the `:actions` slot.
      # No way for the user to fire the event in this state.
      {:ok, view, html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      refute html =~ "file all"
      refute html =~ "phx-click=\"file_all\""

      # No undo flash is queued either.
      _ = :sys.get_state(view.pid)
      refute render(view) =~ ~s(id="undo-toast")
    end
  end

  describe "inline edit on filing-tray drafts — Slice 10B / M-62" do
    setup ctx do
      user = make_user("edit_action_#{System.unique_integer([:positive])}@example.com")
      conversation = make_conversation(user)
      _message = make_message(conversation)
      conn = log_in(ctx.conn, user)

      {:ok, conn: conn, user: user, conversation: conversation}
    end

    test "edit pill swaps the read-only card for the edit form", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "EDIT-OPEN")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("article[id='drafts-#{draft.id}'] button[phx-click='edit_draft']")
      |> render_click()

      html = render(view)
      assert html =~ "filing_tray__edit"
      assert html =~ ~s(name="draft[slug]")
      assert html =~ "EDIT-OPEN"
      # `save` and `cancel` pills are present
      assert html =~ ~s(phx-click="cancel_edit")
      # The read-only "discard" pill is gone while in edit mode
      refute html =~ ~r/article\[id='drafts-#{draft.id}'\].*phx-click="discard"/s
    end

    test "cancel reverts to the read-only draft", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "EDIT-CANCEL")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("article[id='drafts-#{draft.id}'] button[phx-click='edit_draft']")
      |> render_click()

      assert render(view) =~ "filing_tray__edit"

      view
      |> element("article[id='drafts-#{draft.id}'] button[phx-click='cancel_edit']")
      |> render_click()

      html = render(view)
      refute html =~ "filing_tray__edit"
      # Read-only view restored
      assert html =~ "ANT · 1177BC · EDIT-CANCEL"
    end

    test "save with content-only change updates front + back, leaves call_number untouched",
         ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "EDIT-CONTENT")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("article[id='drafts-#{draft.id}'] button[phx-click='edit_draft']")
      |> render_click()

      view
      |> form("article[id='drafts-#{draft.id}'] form", %{
        "card_id" => draft.id,
        "draft" => %{
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "EDIT-CONTENT",
          "front" => "Reworked front",
          "back" => "Reworked back"
        }
      })
      |> render_submit()

      saved = Ash.get!(Manillum.Archive.Card, draft.id, authorize?: false)
      assert saved.front == "Reworked front"
      assert saved.back == "Reworked back"
      assert saved.slug == "EDIT-CONTENT"
      assert saved.drawer == :ANT
      assert saved.date_token == "1177BC"

      # Form is gone, read-only renders the new content
      html = render(view)
      refute html =~ "filing_tray__edit"
      assert html =~ "Reworked front"
    end

    test "save with slug rename writes a CallNumberRedirect", ctx do
      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "OLD-SLUG")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("article[id='drafts-#{draft.id}'] button[phx-click='edit_draft']")
      |> render_click()

      view
      |> form("article[id='drafts-#{draft.id}'] form", %{
        "card_id" => draft.id,
        "draft" => %{
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "NEW-SLUG",
          "front" => "front for OLD-SLUG",
          "back" => "back for OLD-SLUG"
        }
      })
      |> render_submit()

      saved = Ash.get!(Manillum.Archive.Card, draft.id, authorize?: false)
      assert saved.slug == "NEW-SLUG"

      redirects =
        Manillum.Archive.CallNumberRedirect
        |> Ash.Query.filter(current_card_id == ^draft.id)
        |> Ash.read!(authorize?: false)

      assert length(redirects) == 1
      assert hd(redirects).slug == "OLD-SLUG"
    end

    test "validate_edit surfaces a slug-collision warning when segments match an existing card",
         ctx do
      # Seed a filed card to collide against
      _existing =
        Ash.Seed.seed!(Manillum.Archive.Card, %{
          user_id: ctx.user.id,
          drawer: :ANT,
          date_token: "1177BC",
          slug: "TAKEN",
          card_type: :event,
          front: "F",
          back: "B",
          status: :filed
        })

      capture = seed_capture(ctx.user, ctx.conversation)
      draft = seed_draft(ctx.user, capture, "EDIT-COLLIDE")

      {:ok, view, _html} = live(ctx.conn, ~p"/conversations/#{ctx.conversation.id}")

      view
      |> element("article[id='drafts-#{draft.id}'] button[phx-click='edit_draft']")
      |> render_click()

      view
      |> form("article[id='drafts-#{draft.id}'] form", %{
        "card_id" => draft.id,
        "draft" => %{
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "TAKEN",
          "front" => "front for EDIT-COLLIDE",
          "back" => "back for EDIT-COLLIDE"
        }
      })
      |> render_change()

      html = render(view)
      assert html =~ "filing_tray__edit-collision"
      assert html =~ "collides with an existing filed card"
    end
  end

  # Fire the file_card event directly at the FilingTrayComponent. The
  # rendered click goes through the JS command pipeline (add_class /
  # remove_attribute / push) which is overkill for unit assertions
  # since we care about server-side state changes.
  defp send_file_card(view, draft_id) do
    view
    |> element("article[id='drafts-#{draft_id}'] .action_pill--primary")
    |> render_click()
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
