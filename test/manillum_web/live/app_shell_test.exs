defmodule ManillumWeb.AppShellTest do
  @moduledoc """
  Smoke test for the M-32 app-shell skeleton: every route under the
  authenticated live session redirects unauthenticated users to /sign-in,
  and renders the shared shell (active tab + sign-out) for logged-in
  users. Proves both the routes are mounted and the auth gate is wired.
  """
  use ManillumWeb.ConnCase

  import Phoenix.LiveViewTest

  # Routes that still render the M-32 stub_page (placeholder copy + back-to-today link).
  @stub_routes [
    {"/conversations/new", "conversations"},
    {"/quiz", "quiz"}
  ]

  # Real LiveViews wrapped in the same shell — exercise the active-tab
  # indicator without requiring the placeholder copy. The browse views
  # below ship in Stream F / M-29.
  @real_routes [
    {"/", "today"},
    {"/conversations", "conversations"},
    {"/catalog", "catalog"},
    {"/drawers", "drawers"},
    {"/drawers/ANT", "drawers"},
    {"/reference", "reference"}
  ]

  # /cards/:id is real but needs a seeded card (or it push_navigates to
  # /catalog on not-found). Auth gate is tested separately below.
  @all_routes @real_routes ++ @stub_routes

  describe "auth gate" do
    for {path, _tab} <- @all_routes do
      test "GET #{path} redirects unauthenticated users to sign-in", %{conn: conn} do
        conn = get(conn, unquote(path))
        assert redirected_to(conn) =~ "/sign-in"
      end
    end

    test "GET /cards/:id redirects unauthenticated users to sign-in", %{conn: conn} do
      conn = get(conn, "/cards/00000000-0000-0000-0000-000000000000")
      assert redirected_to(conn) =~ "/sign-in"
    end
  end

  describe "authenticated shell" do
    setup :sign_in_user

    for {path, tab} <- @all_routes do
      test "GET #{path} renders shell with active tab #{tab}", %{conn: conn} do
        {:ok, _view, html} = live(conn, unquote(path))

        # Active-tab indicator: the matching topbar nav link carries
        # `aria-current="page"`. Substring-match keeps the test cheap.
        active_link =
          ~r"<a[^>]+href=\"/[^\"]*\"[^>]+aria-current=\"page\"[^>]*>\s*#{unquote(tab) |> String.capitalize()}\s*</a>"i

        assert Regex.match?(active_link, html),
               "expected active-tab link for tab '#{unquote(tab)}' on #{unquote(path)}"

        # Shell sign-out link is rendered for logged-in users.
        assert html =~ "/sign-out"
        assert html =~ "sign out"
      end
    end

    for {path, _tab} <- @stub_routes do
      test "GET #{path} renders the stub-page back-to-today affordance", %{conn: conn} do
        {:ok, _view, html} = live(conn, unquote(path))
        assert html =~ "back to today"
      end
    end
  end

  defp sign_in_user(%{conn: conn}) do
    user =
      Ash.Seed.seed!(Manillum.Accounts.User, %{
        email: "shell-test-#{System.unique_integer([:positive])}@example.com"
      })

    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user = %{user | __metadata__: Map.put(user.__metadata__, :token, token)}

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user}
  end
end
