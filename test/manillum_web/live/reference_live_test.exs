defmodule ManillumWeb.ReferenceLiveTest do
  use ManillumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Manillum.Archive
  alias Manillum.Archive.Card

  defp make_user(suffix) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{
      email: "reference_#{suffix}_#{System.unique_integer([:positive])}@example.com"
    })
  end

  defp log_in(conn, user) do
    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(user)
    user = %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp seed_filed(user, attrs) do
    base = %{
      user_id: user.id,
      drawer: :ANT,
      date_token: "1177BC",
      slug: "DEFAULT",
      card_type: :event,
      front: "Front · default",
      back: "Back · default",
      status: :filed
    }

    Ash.Seed.seed!(Card, Map.merge(base, attrs))
  end

  describe "tabs" do
    setup ctx do
      user = make_user("tabs")
      conn = log_in(ctx.conn, user)

      seed_filed(user, %{
        slug: "HANNIBAL",
        card_type: :person,
        front: "Hannibal Barca"
      })

      seed_filed(user, %{
        slug: "ALEXANDRIA",
        card_type: :place,
        front: "The Library of Alexandria"
      })

      seed_filed(user, %{
        slug: "HERODOTUS",
        card_type: :source,
        front: "Herodotus' Histories"
      })

      {:ok, conn: conn, user: user}
    end

    test "default tab is People", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/reference")

      assert html =~ "People, places, sources, themes"
      assert html =~ "HANNIBAL"
      assert html =~ "Hannibal Barca"
      refute html =~ "ALEXANDRIA"
    end

    test "switching to Places shows only place cards", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/reference?tab=places")

      assert html =~ "ALEXANDRIA"
      assert html =~ "The Library of Alexandria"
      refute html =~ "HANNIBAL"
    end

    test "switching to Sources shows only source cards", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/reference?tab=sources")

      assert html =~ "HERODOTUS"
      refute html =~ "HANNIBAL"
    end

    test "Themes tab lists tags with counts", ctx do
      tag = Archive.find_or_create_tag!(ctx.user.id, "Bronze Age")
      seed_filed(ctx.user, %{slug: "COLLAPSE"})

      require Ash.Query

      [bronze] =
        Card
        |> Ash.Query.filter(slug == "COLLAPSE")
        |> Ash.read!()

      Archive.tag_card!(bronze.id, tag.id)

      {:ok, _view, html} = live(ctx.conn, ~p"/reference?tab=themes")

      assert html =~ "Bronze Age"
      assert html =~ "1 card"
    end

    test "empty bucket renders an empty state", ctx do
      user = make_user("empty_bucket")
      conn = log_in(ctx.conn, user)
      {:ok, _view, html} = live(conn, ~p"/reference?tab=places")
      assert html =~ "No places indexed yet"
    end
  end
end
