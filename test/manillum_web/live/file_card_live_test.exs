defmodule ManillumWeb.FileCardLiveTest do
  use ManillumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Manillum.Archive.Card

  require Ash.Query

  defp make_user(email) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{email: email})
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user_with_token = %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user_with_token)
  end

  defp seed_card(user, slug, status) do
    Ash.Seed.seed!(Card, %{
      user_id: user.id,
      drawer: :ANT,
      date_token: "1177BC",
      slug: slug,
      card_type: :event,
      front: "Original front · " <> slug,
      back: "Original back · " <> slug,
      status: status
    })
  end

  describe "auth gate" do
    test "redirects unauthenticated users to sign-in", %{conn: conn} do
      conn = get(conn, "/cards/00000000-0000-0000-0000-000000000000/edit")
      assert redirected_to(conn) =~ "/sign-in"
    end
  end

  describe "mount" do
    setup ctx do
      user = make_user("file_card_mount_#{System.unique_integer([:positive])}@example.com")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders the editor for a draft card with the form pre-filled", ctx do
      card = seed_card(ctx.user, "MOUNT-DRAFT", :draft)

      {:ok, _view, html} = live(ctx.conn, ~p"/cards/#{card.id}/edit")

      assert html =~ "ANT · 1177BC · MOUNT-DRAFT"
      assert html =~ "DRAFT"
      # Form fields pre-filled
      assert html =~ ~s(value="MOUNT-DRAFT")
      assert html =~ "Original front · MOUNT-DRAFT"
      assert html =~ "Original back · MOUNT-DRAFT"
      # Save & file pill present (draft only)
      assert html =~ ~s(value="save_and_file")
    end

    test "renders the editor for a filed card; save & file is hidden", ctx do
      card = seed_card(ctx.user, "MOUNT-FILED", :filed)

      {:ok, _view, html} = live(ctx.conn, ~p"/cards/#{card.id}/edit")

      assert html =~ "ANT · 1177BC · MOUNT-FILED"
      assert html =~ "FILED"
      refute html =~ ~s(value="save_and_file")
    end

    test "missing card id redirects to /catalog with a flash", ctx do
      assert {:error, {:live_redirect, %{to: "/catalog"}}} =
               live(ctx.conn, ~p"/cards/00000000-0000-0000-0000-000000000000/edit")
    end
  end

  describe "save (content-only edit)" do
    setup ctx do
      user = make_user("file_card_save_#{System.unique_integer([:positive])}@example.com")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "updates front + back and stays on the page", ctx do
      card = seed_card(ctx.user, "SAVE-CONTENT", :draft)

      {:ok, view, _html} = live(ctx.conn, ~p"/cards/#{card.id}/edit")

      view
      |> form(".file_card__form", %{
        "card" => %{
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "SAVE-CONTENT",
          "front" => "Edited front",
          "back" => "Edited back",
          "card_type" => "event",
          "entities" => ""
        }
      })
      |> render_submit(%{"action" => "save"})

      saved = Ash.get!(Card, card.id, authorize?: false)
      assert saved.front == "Edited front"
      assert saved.back == "Edited back"
      assert saved.status == :draft
      assert saved.slug == "SAVE-CONTENT"
    end

    test "save with a slug rename writes a CallNumberRedirect", ctx do
      card = seed_card(ctx.user, "OLD-SAVE", :draft)

      {:ok, view, _html} = live(ctx.conn, ~p"/cards/#{card.id}/edit")

      view
      |> form(".file_card__form", %{
        "card" => %{
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "NEW-SAVE",
          "front" => card.front,
          "back" => card.back,
          "card_type" => "event",
          "entities" => ""
        }
      })
      |> render_submit(%{"action" => "save"})

      saved = Ash.get!(Card, card.id, authorize?: false)
      assert saved.slug == "NEW-SAVE"

      redirects =
        Manillum.Archive.CallNumberRedirect
        |> Ash.Query.filter(current_card_id == ^card.id)
        |> Ash.read!(authorize?: false)

      assert length(redirects) == 1
      assert hd(redirects).slug == "OLD-SAVE"
    end

    test "save & file flips status and redirects", ctx do
      card = seed_card(ctx.user, "SAVE-AND-FILE", :draft)

      {:ok, view, _html} = live(ctx.conn, ~p"/cards/#{card.id}/edit")

      assert {:error, {:live_redirect, %{to: redirect}}} =
               view
               |> form(".file_card__form", %{
                 "card" => %{
                   "drawer" => "ANT",
                   "date_token" => "1177BC",
                   "slug" => "SAVE-AND-FILE",
                   "front" => "F",
                   "back" => "B",
                   "card_type" => "event",
                   "entities" => ""
                 }
               })
               |> render_submit(%{"action" => "save_and_file"})

      saved = Ash.get!(Card, card.id, authorize?: false)
      assert saved.status == :filed
      assert redirect == "/catalog"
    end

    test "validate surfaces a slug-collision warning when segments match a filed card", ctx do
      _existing = seed_card(ctx.user, "TAKEN-SLUG", :filed)
      draft = seed_card(ctx.user, "FREE-SLUG", :draft)

      {:ok, view, _html} = live(ctx.conn, ~p"/cards/#{draft.id}/edit")

      view
      |> form(".file_card__form", %{
        "card" => %{
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "TAKEN-SLUG",
          "front" => draft.front,
          "back" => draft.back,
          "card_type" => "event",
          "entities" => ""
        }
      })
      |> render_change()

      html = render(view)
      assert html =~ "file_card__collision"
      assert html =~ "collides with an existing filed card"
    end

    test "entities parses comma-separated values and persists", ctx do
      card = seed_card(ctx.user, "ENTITIES-SAVE", :draft)

      {:ok, view, _html} = live(ctx.conn, ~p"/cards/#{card.id}/edit")

      view
      |> form(".file_card__form", %{
        "card" => %{
          "drawer" => "ANT",
          "date_token" => "1177BC",
          "slug" => "ENTITIES-SAVE",
          "front" => card.front,
          "back" => card.back,
          "card_type" => "event",
          "entities" => "Hannibal, Roman Republic , Carthage"
        }
      })
      |> render_submit(%{"action" => "save"})

      saved = Ash.get!(Card, card.id, authorize?: false)
      assert saved.entities == ["Hannibal", "Roman Republic", "Carthage"]
    end
  end

  describe "cancel" do
    setup ctx do
      user = make_user("file_card_cancel_#{System.unique_integer([:positive])}@example.com")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "filed card cancel navigates back to /cards/:id", ctx do
      card = seed_card(ctx.user, "CANCEL-FILED", :filed)

      {:ok, view, _html} = live(ctx.conn, ~p"/cards/#{card.id}/edit")

      assert {:error, {:live_redirect, %{to: redirect}}} =
               view |> element("button[phx-click='cancel']") |> render_click()

      assert redirect == "/cards/#{card.id}"
    end
  end
end
