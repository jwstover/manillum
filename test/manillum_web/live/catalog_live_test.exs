defmodule ManillumWeb.CatalogLiveTest do
  use ManillumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Manillum.Archive
  alias Manillum.Archive.Card

  require Ash.Query

  defp make_user(suffix) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{
      email: "catalog_#{suffix}_#{System.unique_integer([:positive])}@example.com"
    })
  end

  defp log_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
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

  describe "mount" do
    setup ctx do
      user = make_user("mount")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders the catalog header and search bar", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/catalog")

      assert html =~ "Search the catalog"
      assert html =~ "QUERY"
      # 0 cards rendered as a count
      assert html =~ "0"
    end

    test "renders an empty state when no cards are filed", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/catalog")

      assert html =~ "Nothing&#39;s been filed yet" or html =~ "Nothing's been filed yet"
    end
  end

  describe "browse + search" do
    setup ctx do
      user = make_user("browse")
      conn = log_in(ctx.conn, user)

      seed_filed(user, %{slug: "COLLAPSE", front: "Bronze Age collapse", drawer: :ANT})

      seed_filed(user, %{
        slug: "LEONARDO",
        date_token: "1519",
        front: "Leonardo at Clos Lucé",
        drawer: :REN,
        card_type: :person
      })

      {:ok, conn: conn, user: user}
    end

    test "renders both seeded cards", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/catalog")

      assert html =~ "ANT · 1177BC · COLLAPSE"
      assert html =~ "REN · 1519 · LEONARDO"
      assert html =~ "Bronze Age collapse"
      assert html =~ "Leonardo at Clos Lucé"
    end

    test "free-text search filters by front", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/catalog")

      view
      |> form(".catalog__search", %{"q" => "Leonardo"})
      |> render_change()

      html = render(view)
      assert html =~ "REN · 1519 · LEONARDO"
      refute html =~ "ANT · 1177BC · COLLAPSE"
    end

    test "drawer filter narrows results", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/catalog")

      html = render_click(view, "filter_drawer", %{"drawer" => "ANT"})
      assert html =~ "ANT · 1177BC · COLLAPSE"
      refute html =~ "REN · 1519 · LEONARDO"
    end

    test "card-type filter narrows results", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/catalog")

      html = render_click(view, "filter_type", %{"type" => "person"})
      assert html =~ "REN · 1519 · LEONARDO"
      refute html =~ "ANT · 1177BC · COLLAPSE"
    end

    test "clear button resets filters", ctx do
      {:ok, view, _} = live(ctx.conn, ~p"/catalog?drawer=ANT")
      assert render(view) =~ "ANT · 1177BC · COLLAPSE"
      refute render(view) =~ "REN · 1519 · LEONARDO"

      html = render_click(view, "clear", %{})
      assert html =~ "ANT · 1177BC · COLLAPSE"
      assert html =~ "REN · 1519 · LEONARDO"
    end

    test "tag filter narrows results", ctx do
      tag = Archive.find_or_create_tag!(ctx.user.id, "Renaissance")

      # Tag the Leonardo card
      [leo] =
        Card
        |> Ash.Query.filter(slug == "LEONARDO")
        |> Ash.read!()

      Archive.tag_card!(leo.id, tag.id)

      {:ok, _view, html} = live(ctx.conn, ~p"/catalog?tag=#{tag.id}")

      assert html =~ "REN · 1519 · LEONARDO"
      refute html =~ "ANT · 1177BC · COLLAPSE"
    end
  end

  describe "scope isolation" do
    test "other users' cards do not appear", ctx do
      me = make_user("isolation_me")
      other = make_user("isolation_other")

      seed_filed(me, %{slug: "MINE", front: "My fact"})
      seed_filed(other, %{slug: "THEIRS", front: "Their fact"})

      conn = log_in(ctx.conn, me)
      {:ok, _view, html} = live(conn, ~p"/catalog")

      assert html =~ "MINE"
      refute html =~ "THEIRS"
    end
  end
end
