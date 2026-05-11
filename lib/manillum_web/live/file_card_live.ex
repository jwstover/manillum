defmodule ManillumWeb.FileCardLive do
  @moduledoc """
  Full-screen editor for a single Card. Routed to from per-draft Edit
  in the filing tray (M-62 will swap to navigate here for fuller edits)
  and from `/cards/:id` Edit for already-filed cards.

  Reuses Stream B's `:rename` and M-62's `:edit_content` actions. The
  page dispatches to the right action(s) on submit based on what
  changed.

  Three save paths:

    * **Save** — applies edits and stays on the page.
    * **Save & file** — applies edits and runs `Card.:file`. Only
      visible on draft cards. Navigates back to the conversation that
      produced the source capture (or `/catalog` if there's no
      conversation provenance).
    * **Cancel** — navigates back to wherever the user came from
      (`/cards/:id` for filed cards, the source conversation for
      drafts).
  """

  use ManillumWeb, :live_view

  import ManillumWeb.CardHelpers

  alias Manillum.Archive
  alias Manillum.Archive.Card
  alias Manillum.Archive.Card.CallNumberProposal
  alias ManillumWeb.ManillumComponents

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case load_card(id, actor) do
      {:ok, card} ->
        {:ok,
         socket
         |> assign(:card, card)
         |> assign(:form, build_form(card))
         |> assign(:collision, nil)
         |> assign(:page_title, "Edit · " <> (card.call_number || ""))}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Card not found.")
         |> push_navigate(to: ~p"/catalog")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_tab="catalog">
      <div class="file_card">
        <header class="file_card__head">
          <ManillumComponents.meta_label tone={:oxblood}>
            ● Manillum · edit card
          </ManillumComponents.meta_label>
          <h1 class="file_card__title">{@card.call_number}</h1>
          <p class="file_card__sub">
            {status_label(@card.status)} · last updated {format_dt(@card.updated_at)}
          </p>
        </header>

        <div class="file_card__preview">
          <ManillumComponents.card face={preview_face(@card.status)}>
            <div class="file_card__preview-head">
              <ManillumComponents.call_number inline>
                {@card.call_number}
              </ManillumComponents.call_number>
              <ManillumComponents.stamp :if={@card.status == :filed} variant={:small}>
                FILED
              </ManillumComponents.stamp>
              <ManillumComponents.stamp :if={@card.status == :draft} variant={:small}>
                DRAFT
              </ManillumComponents.stamp>
            </div>
            <ManillumComponents.drawer_label>
              {drawer_name(@card.drawer)}
            </ManillumComponents.drawer_label>
            <div class="file_card__preview-front">
              {@form.params["front"] || @card.front}
            </div>
            <div class="file_card__preview-back">
              {@form.params["back"] || @card.back}
            </div>
          </ManillumComponents.card>
        </div>

        <.form
          for={@form}
          as={:card}
          phx-change="validate"
          phx-submit="save"
          class="file_card__form"
        >
          <section class="file_card__section">
            <h2 class="file_card__section-head">Identity</h2>

            <div class="file_card__row">
              <label class="file_card__label" for="card-drawer">
                <span class="file_card__label-text">drawer</span>
                <select
                  name="card[drawer]"
                  id="card-drawer"
                  class="file_card__input"
                >
                  <option
                    :for={d <- ~w(ANT CLA MED REN EAR MOD CON)}
                    value={d}
                    selected={to_string(@form.params["drawer"]) == d}
                  >
                    {d} · {drawer_name(String.to_existing_atom(d))}
                  </option>
                </select>
              </label>
              <label class="file_card__label" for="card-date_token">
                <span class="file_card__label-text">date</span>
                <input
                  type="text"
                  name="card[date_token]"
                  id="card-date_token"
                  value={@form.params["date_token"]}
                  class="file_card__input file_card__input--mono"
                />
              </label>
              <label class="file_card__label file_card__label--grow" for="card-slug">
                <span class="file_card__label-text">slug</span>
                <input
                  type="text"
                  name="card[slug]"
                  id="card-slug"
                  value={@form.params["slug"]}
                  class="file_card__input file_card__input--mono file_card__input--upper"
                />
              </label>
            </div>

            <div :if={@collision} class="file_card__collision">
              <.icon name="hero-exclamation-triangle-micro" /> collides with an existing filed card
            </div>
          </section>

          <section class="file_card__section">
            <h2 class="file_card__section-head">Content</h2>

            <label class="file_card__label file_card__label--block" for="card-front">
              <span class="file_card__label-text">front · question</span>
              <textarea
                name="card[front]"
                id="card-front"
                rows="3"
                class="file_card__input file_card__input--front"
              >{@form.params["front"]}</textarea>
            </label>

            <label class="file_card__label file_card__label--block" for="card-back">
              <span class="file_card__label-text">back · fact</span>
              <textarea
                name="card[back]"
                id="card-back"
                rows="8"
                class="file_card__input file_card__input--back"
              >{@form.params["back"]}</textarea>
            </label>
          </section>

          <section class="file_card__section">
            <h2 class="file_card__section-head">Metadata</h2>

            <label class="file_card__label" for="card-card_type">
              <span class="file_card__label-text">card type</span>
              <select
                name="card[card_type]"
                id="card-card_type"
                class="file_card__input"
              >
                <option
                  :for={t <- ~w(person event place concept source date artifact)}
                  value={t}
                  selected={to_string(@form.params["card_type"]) == t}
                >
                  {t}
                </option>
              </select>
            </label>

            <label class="file_card__label file_card__label--block" for="card-entities">
              <span class="file_card__label-text">
                entities · comma-separated
              </span>
              <input
                type="text"
                name="card[entities]"
                id="card-entities"
                value={@form.params["entities"]}
                placeholder="e.g. Hannibal, Roman Republic, Carthage"
                class="file_card__input"
              />
            </label>
          </section>

          <div class="file_card__actions">
            <button type="submit" name="action" value="save" class="action_pill action_pill--primary">
              save
            </button>
            <button
              :if={@card.status == :draft}
              type="submit"
              name="action"
              value="save_and_file"
              class="action_pill action_pill--primary"
            >
              <.icon name="hero-archive-box-micro" /> save &amp; file
            </button>
            <span class="file_card__actions-spacer" aria-hidden="true"></span>
            <button
              type="button"
              class="action_pill action_pill--bare"
              phx-click="cancel"
            >
              cancel
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"card" => params}, socket) do
    form = to_form(params, as: "card")
    collision = propose_collision(socket.assigns.card, params, socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:collision, collision)}
  end

  def handle_event("save", %{"card" => params} = full_params, socket) do
    actor = socket.assigns.current_user
    action = full_params["action"] || "save"

    with {:ok, card} <- maybe_rename(socket.assigns.card, params, actor),
         {:ok, card} <- maybe_edit_content(card, params, actor),
         {:ok, card} <- maybe_file(card, action, actor) do
      card = reload_card(card, actor)

      socket =
        socket
        |> assign(:card, card)
        |> assign(:form, build_form(card))
        |> assign(:collision, nil)
        |> put_flash(:ok, save_flash(action))

      case action do
        "save_and_file" ->
          {:noreply, push_navigate(socket, to: post_file_redirect(card))}

        _ ->
          {:noreply, socket}
      end
    else
      {:error, %Ash.Error.Invalid{} = err} ->
        {:noreply, put_flash(socket, :error, format_invalid(err))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't save the card.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, push_navigate(socket, to: cancel_redirect(socket.assigns.card))}
  end

  # ──────────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────────

  defp load_card(id, actor) do
    Ash.get(Card, id,
      actor: actor,
      load: [
        :call_number,
        capture: [:conversation, :message],
        collision_card: [:call_number]
      ]
    )
  end

  defp reload_card(card, actor) do
    Ash.load!(
      card,
      [:call_number, capture: [:conversation, :message], collision_card: [:call_number]],
      actor: actor
    )
  end

  defp build_form(card) do
    to_form(
      %{
        "drawer" => to_string(card.drawer),
        "date_token" => card.date_token,
        "slug" => card.slug,
        "front" => card.front,
        "back" => card.back,
        "card_type" => to_string(card.card_type),
        "entities" => Enum.join(card.entities || [], ", ")
      },
      as: "card"
    )
  end

  defp maybe_rename(card, params, actor) do
    new_drawer = atomize_drawer(params["drawer"]) || card.drawer
    new_date = (params["date_token"] || card.date_token) |> nil_if_blank() || card.date_token
    new_slug = (params["slug"] || card.slug) |> nil_if_blank() || card.slug

    if {new_drawer, new_date, new_slug} == {card.drawer, card.date_token, card.slug} do
      {:ok, card}
    else
      card
      |> Ash.Changeset.for_update(
        :rename,
        %{drawer: new_drawer, date_token: new_date, slug: new_slug},
        actor: actor
      )
      |> Ash.update()
    end
  end

  defp maybe_edit_content(card, params, actor) do
    new_front = params["front"] || card.front
    new_back = params["back"] || card.back
    new_card_type = atomize_card_type(params["card_type"]) || card.card_type
    new_entities = parse_entities(params["entities"], card.entities)

    if new_front == card.front and new_back == card.back and
         new_card_type == card.card_type and new_entities == (card.entities || []) do
      {:ok, card}
    else
      card
      |> Ash.Changeset.for_update(
        :edit_content,
        %{
          front: new_front,
          back: new_back,
          card_type: new_card_type,
          entities: new_entities
        },
        actor: actor
      )
      |> Ash.update()
    end
  end

  defp maybe_file(%{status: :draft} = card, "save_and_file", actor) do
    Archive.file_card(card, actor: actor)
  end

  defp maybe_file(card, _, _), do: {:ok, card}

  defp propose_collision(self_card, params, actor) do
    drawer = atomize_drawer(params["drawer"])
    date_token = params["date_token"] || ""
    slug = params["slug"] || ""

    with true <- drawer != nil,
         true <- date_token != "",
         true <- slug != "",
         {:ok, %CallNumberProposal{status: :collision, existing_card_id: id}} <-
           Card
           |> Ash.ActionInput.for_action(:propose_call_number, %{
             user_id: actor.id,
             drawer: drawer,
             date_token: date_token,
             slug: slug,
             card_type: self_card.card_type
           })
           |> Ash.run_action(authorize?: false),
         true <- id != self_card.id do
      %{existing_card_id: id}
    else
      _ -> nil
    end
  end

  defp atomize_card_type(value) when is_binary(value) and value != "" do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp atomize_card_type(_), do: nil

  defp parse_entities(nil, fallback), do: fallback || []

  defp parse_entities(text, _fallback) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_entities(_, fallback), do: fallback || []

  defp nil_if_blank(""), do: nil
  defp nil_if_blank(value), do: value

  defp save_flash("save_and_file"),
    do: %{kicker: "● FILED", title: "Filed and saved."}

  defp save_flash(_), do: "Saved."

  defp post_file_redirect(%{capture: %{conversation: %{id: cid}}}) when is_binary(cid),
    do: ~p"/conversations/#{cid}"

  defp post_file_redirect(_), do: ~p"/catalog"

  defp cancel_redirect(%{status: :draft, capture: %{conversation: %{id: cid}}})
       when is_binary(cid),
       do: ~p"/conversations/#{cid}"

  defp cancel_redirect(%{id: id}), do: ~p"/cards/#{id}"

  defp status_label(:draft), do: "DRAFT"
  defp status_label(:filed), do: "FILED"
  defp status_label(:archived), do: "ARCHIVED"
  defp status_label(other), do: to_string(other) |> String.upcase()

  defp preview_face(:draft), do: :draft
  defp preview_face(_), do: :recto

  defp format_dt(%DateTime{} = dt) do
    date = DateTime.to_date(dt)
    "#{date.year}-#{pad(date.month)}-#{pad(date.day)}"
  end

  defp format_dt(%NaiveDateTime{} = dt) do
    date = NaiveDateTime.to_date(dt)
    "#{date.year}-#{pad(date.month)}-#{pad(date.day)}"
  end

  defp format_dt(_), do: "—"

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
