defmodule ManillumWeb.PageController do
  use ManillumWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
