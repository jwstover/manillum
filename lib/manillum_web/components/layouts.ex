defmodule ManillumWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ManillumWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the signed-in Manillum.Accounts.User"

  attr :pin_year, :integer, default: nil
  attr :pin_label, :string, default: nil
  attr :active_tab, :string, default: nil
  attr :meta, :string, default: nil
  attr :show_era_band, :boolean, default: true

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.page>
      <.topbar active={@active_tab} meta={@meta}>
        <:tab id="today" href={~p"/"}>Today</:tab>
        <:tab id="conversations" href={~p"/conversations"}>Conversations</:tab>
        <:tab id="catalog" href={~p"/catalog"}>Catalog</:tab>
        <:tab id="drawers" href={~p"/drawers"}>Drawers</:tab>
        <:tab id="reference" href={~p"/reference"}>Reference</:tab>
        <:tab id="quiz" href={~p"/quiz"}>Quiz</:tab>
        <:end_ :if={@current_user}>
          <span class="topbar__user">{user_display(@current_user)}</span>
          <.link href={~p"/sign-out"} method="delete" class="topbar__signout">
            sign out
          </.link>
        </:end_>
      </.topbar>
      <.era_band :if={@show_era_band} pin_year={@pin_year} pin_label={@pin_label} />
      <main>
        {render_slot(@inner_block)}
      </main>
      <.flash_group flash={@flash} />
    </.page>
    """
  end

  # Display name for the topbar identity strip. The MVP user resource has
  # an `email` `Ash.CIString` attribute (magic-link auth). First name /
  # display fields may land later.
  defp user_display(%{email: email}), do: to_string(email)
  defp user_display(_), do: ""

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="toast_stack" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:ok} flash={@flash} />
      <.flash kind={:warn} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        kicker="● OFFLINE"
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        kicker="● ERROR"
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
