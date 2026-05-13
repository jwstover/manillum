defmodule ManillumWeb.CardLiveTest do
  use ManillumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Manillum.Archive
  alias Manillum.Archive.Card
  alias Manillum.Archive.Capture
  alias Manillum.Conversations.Conversation
  alias Manillum.Conversations.Message

  defp make_user(suffix) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{
      email: "card_#{suffix}_#{System.unique_integer([:positive])}@example.com"
    })
  end

  defp log_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)
    user = %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp seed_filed(user, attrs \\ %{}) do
    base = %{
      user_id: user.id,
      drawer: :ANT,
      date_token: "1177BC",
      slug: "COLLAPSE",
      card_type: :event,
      front: "What was the Bronze Age collapse?",
      back: "A systems collapse around 1177 BCE.",
      status: :filed
    }

    Ash.Seed.seed!(Card, Map.merge(base, attrs))
  end

  describe "mount" do
    setup ctx do
      user = make_user("mount")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders the card detail surface (recto + verso + meta)", ctx do
      card = seed_filed(ctx.user)

      {:ok, _view, html} = live(ctx.conn, ~p"/cards/#{card.id}")

      # Call number stamped on both faces
      assert html =~ "ANT · 1177BC · COLLAPSE"
      # Recto question + verso answer
      assert html =~ "What was the Bronze Age collapse?"
      assert html =~ "A systems collapse around 1177 BCE."
      # Drawer label
      assert html =~ "Antiquity"
      # Status pill
      assert html =~ "Filed"
      # Edit link visible
      assert html =~ "edit this card"
    end

    test "missing card redirects to /catalog with a flash", ctx do
      assert {:error, {:live_redirect, %{to: "/catalog"}}} =
               live(ctx.conn, ~p"/cards/00000000-0000-0000-0000-000000000000")
    end

    test "other user's card is treated as not found", ctx do
      stranger = make_user("stranger")
      card = seed_filed(stranger)

      assert {:error, {:live_redirect, %{to: "/catalog"}}} =
               live(ctx.conn, ~p"/cards/#{card.id}")
    end
  end

  describe "see-also + related-by-tag" do
    setup ctx do
      user = make_user("relations")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders see-also partners", ctx do
      a = seed_filed(ctx.user, %{slug: "COLLAPSE-A"})
      b = seed_filed(ctx.user, %{slug: "SEA-PEOPLES", date_token: "1200BC"})

      Archive.link!(%{from_card_id: a.id, to_card_id: b.id, kind: :see_also})

      {:ok, _view, html} = live(ctx.conn, ~p"/cards/#{a.id}")

      assert html =~ "See also"
      assert html =~ "ANT · 1200BC · SEA-PEOPLES"
    end

    test "renders related-by-tag siblings", ctx do
      a = seed_filed(ctx.user, %{slug: "COLLAPSE-B"})
      sibling = seed_filed(ctx.user, %{slug: "UGARIT", date_token: "1180BC"})

      tag = Archive.find_or_create_tag!(ctx.user.id, "Bronze Age")
      Archive.tag_card!(a.id, tag.id)
      Archive.tag_card!(sibling.id, tag.id)

      {:ok, _view, html} = live(ctx.conn, ~p"/cards/#{a.id}")

      assert html =~ "Related by tag"
      assert html =~ "ANT · 1180BC · UGARIT"
    end
  end

  describe "provenance" do
    setup ctx do
      user = make_user("provenance")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders provenance link back to the source conversation/message", ctx do
      conversation =
        Ash.Seed.seed!(Conversation, %{
          user_id: ctx.user.id,
          title: "About the Bronze Age",
          query_number: System.unique_integer([:positive])
        })

      message =
        Ash.Seed.seed!(Message, %{
          conversation_id: conversation.id,
          role: :assistant,
          content: "A long answer about the Bronze Age."
        })

      capture =
        Ash.Seed.seed!(Capture, %{
          user_id: ctx.user.id,
          source_text: "A long answer about the Bronze Age.",
          scope: :selection,
          selection_start: 0,
          selection_end: 32,
          conversation_id: conversation.id,
          message_id: message.id,
          status: :catalogued
        })

      card = seed_filed(ctx.user, %{capture_id: capture.id, slug: "PROV-1"})

      {:ok, _view, html} = live(ctx.conn, ~p"/cards/#{card.id}")

      assert html =~ "Provenance"
      assert html =~ "your conversation"
      assert html =~ "About the Bronze Age"
      # Link target carries the message anchor for spec §7.2 offset behavior
      assert html =~ "/conversations/#{conversation.id}#message-#{message.id}"
      # Selection scope note surfaces the offsets
      assert html =~ "selection 0–32"
    end

    test "no provenance section when capture is nil", ctx do
      card = seed_filed(ctx.user, %{slug: "NO-PROV"})

      {:ok, _view, html} = live(ctx.conn, ~p"/cards/#{card.id}")

      refute html =~ "back to source"
    end
  end
end
