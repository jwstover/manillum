defmodule ManillumWeb.DrawersLiveTest do
  use ManillumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Manillum.Archive.Card

  defp make_user(suffix) do
    Ash.Seed.seed!(Manillum.Accounts.User, %{
      email: "drawers_#{suffix}_#{System.unique_integer([:positive])}@example.com"
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

  describe "index" do
    setup ctx do
      user = make_user("index")
      conn = log_in(ctx.conn, user)
      {:ok, conn: conn, user: user}
    end

    test "renders all seven drawer cells with counts", ctx do
      seed_filed(ctx.user, %{slug: "ONE", drawer: :ANT})
      seed_filed(ctx.user, %{slug: "TWO", drawer: :REN, date_token: "1519"})

      {:ok, _view, html} = live(ctx.conn, ~p"/drawers")

      assert html =~ "Browse the cabinet"
      assert html =~ "DR. 01"
      assert html =~ "DR. 07"
      assert html =~ "Antiquity"
      assert html =~ "Renaissance"
      # ANT has 1, REN has 1, others 0
      assert html =~ "1 card"
    end

    test "empty user sees all drawers at zero", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/drawers")
      assert html =~ "DR. 01"
      assert html =~ "0 cards"
    end
  end

  describe "show — single drawer" do
    setup ctx do
      user = make_user("show")
      conn = log_in(ctx.conn, user)

      seed_filed(user, %{slug: "EARLIEST", date_token: "1177BC", drawer: :ANT})
      seed_filed(user, %{slug: "MIDDLE", date_token: "500BC", drawer: :ANT})
      seed_filed(user, %{slug: "RENAISSANCE-ITEM", date_token: "1519", drawer: :REN})

      {:ok, conn: conn, user: user}
    end

    test "lists cards in the requested drawer", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/drawers/ANT")

      assert html =~ "Antiquity"
      assert html =~ "ANT · 1177BC · EARLIEST"
      assert html =~ "ANT · 500BC · MIDDLE"
      refute html =~ "RENAISSANCE-ITEM"
    end

    test "sorts chronologically by date_token (BC dates ascending → older first)", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/drawers/ANT")

      earliest_pos = :binary.match(html, "EARLIEST") |> elem(0)
      middle_pos = :binary.match(html, "MIDDLE") |> elem(0)
      assert earliest_pos < middle_pos, "expected 1177BC before 500BC in chronological order"
    end

    test "unknown drawer redirects back to /drawers", ctx do
      assert {:error, {:live_redirect, %{to: "/drawers"}}} =
               live(ctx.conn, ~p"/drawers/XXX")
    end

    test "lowercase drawer code is accepted", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/drawers/ant")
      assert html =~ "Antiquity"
    end

    test "drawer with no cards renders empty state", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/drawers/CON")
      assert html =~ "This drawer is empty" or html =~ "empty"
    end
  end
end
