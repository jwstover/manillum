defmodule ManillumWeb.CardLive do
  @moduledoc """
  Single-card detail view at `/cards/:id`. Renders the recto/verso
  faces, call-number identity, drawer label, tags, entities,
  see-also partners, related-by-tag siblings, and a provenance link
  back to the source conversation/message.

  Shipped in Stream F / Slice 11 (M-29). Reuses the `:rename` +
  `CallNumberRedirect` lookup in `Manillum.Archive.get_card_by_call_number/2`
  via the `id` param being a UUID (lookup-by-call-number is a future
  affordance).
  """

  use ManillumWeb, :live_view

  import ManillumWeb.CardHelpers

  alias Manillum.Archive
  alias ManillumWeb.ManillumComponents

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Archive.get_card_detail(actor.id, id) do
      {:ok, card} ->
        see_also = Archive.see_also_partners(card.id)
        related = Archive.related_by_tag(card)

        {:ok,
         socket
         |> assign(:card, card)
         |> assign(:see_also, see_also)
         |> assign(:related, related)
         |> assign(:page_title, "Card · " <> (card.call_number || ""))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Card not found.")
         |> push_navigate(to: ~p"/catalog")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active_tab="catalog"
      pin_year={pin_year(@card)}
      pin_label={@card.drawer && drawer_short(@card.drawer)}
    >
      <main class="card_detail">
        <header class="card_detail__head">
          <ManillumComponents.kicker>
            ● Manillum · card
          </ManillumComponents.kicker>
          <h1 class="card_detail__title">
            {@card.call_number}
          </h1>
          <div class="card_detail__meta">
            <ManillumComponents.drawer_label>
              {drawer_name(@card.drawer)}
            </ManillumComponents.drawer_label>
            <span class="card_detail__sep" aria-hidden="true">·</span>
            <span class="card_detail__type">{@card.card_type}</span>
            <span class="card_detail__sep" aria-hidden="true">·</span>
            <span class="card_detail__status">
              {status_label(@card.status)}
            </span>
          </div>
        </header>

        <div class="card_detail__faces">
          <ManillumComponents.card face={:recto} class="card_detail__face">
            <ManillumComponents.card_head>
              <ManillumComponents.call_number>
                {@card.call_number}
              </ManillumComponents.call_number>
              <ManillumComponents.stamp variant={:small}>
                Front<br />Recto
              </ManillumComponents.stamp>
            </ManillumComponents.card_head>
            <ManillumComponents.card_question>
              {@card.front}
            </ManillumComponents.card_question>
            <ManillumComponents.card_foot>
              <span>{drawer_short(@card.drawer)}</span>
              <span>Filed {format_date(@card.inserted_at)}</span>
            </ManillumComponents.card_foot>
          </ManillumComponents.card>

          <ManillumComponents.card face={:verso} class="card_detail__face">
            <ManillumComponents.card_head>
              <ManillumComponents.call_number tone={:forest}>
                {@card.call_number}
              </ManillumComponents.call_number>
              <span class="card_detail__verso-mark">
                Back · Verso
              </span>
            </ManillumComponents.card_head>
            <ManillumComponents.card_answer>
              {@card.back}
            </ManillumComponents.card_answer>
          </ManillumComponents.card>
        </div>

        <section :if={tag_list(@card) != []} class="card_detail__section">
          <h2 class="card_detail__section-head">Cross-reference tags</h2>
          <div class="card_detail__tags">
            <ManillumComponents.tag :for={t <- tag_list(@card)}>
              {t.name}
            </ManillumComponents.tag>
          </div>
        </section>

        <section :if={@card.entities != []} class="card_detail__section">
          <h2 class="card_detail__section-head">Entities mentioned</h2>
          <p class="card_detail__entities">
            <span :for={{e, idx} <- Enum.with_index(@card.entities)}>
              <span :if={idx > 0}>, </span>
              <em>{e}</em>
            </span>
          </p>
        </section>

        <section :if={@see_also != []} class="card_detail__section">
          <h2 class="card_detail__section-head">See also</h2>
          <ul class="card_detail__refs">
            <li :for={partner <- @see_also}>
              <.link navigate={~p"/cards/#{partner.id}"} class="card_detail__ref">
                <ManillumComponents.call_number inline>
                  {partner.call_number}
                </ManillumComponents.call_number>
              </.link>
            </li>
          </ul>
        </section>

        <section :if={@related != []} class="card_detail__section">
          <h2 class="card_detail__section-head">Related by tag</h2>
          <ul class="card_detail__refs">
            <li :for={sibling <- @related}>
              <.link navigate={~p"/cards/#{sibling.id}"} class="card_detail__ref">
                <ManillumComponents.call_number inline tone={:brass}>
                  {sibling.call_number}
                </ManillumComponents.call_number>
                <span class="card_detail__ref-title">{sibling.front}</span>
              </.link>
            </li>
          </ul>
        </section>

        <section :if={provenance(@card)} class="card_detail__section">
          <h2 class="card_detail__section-head">Provenance</h2>
          <p class="card_detail__provenance">
            <% prov = provenance(@card) %> From <em>{prov.label}</em>
            <span :if={prov.scope_note} class="card_detail__provenance-scope">
              · {prov.scope_note}
            </span>
            ·
            <.link navigate={prov.path} class="card_detail__provenance-link">
              back to source ⟶
            </.link>
          </p>
        </section>

        <div class="card_detail__actions">
          <.link
            navigate={~p"/cards/#{@card.id}/edit"}
            class="action_pill action_pill--ghost"
          >
            edit this card →
          </.link>
        </div>
      </main>
    </Layouts.app>
    """
  end

  # ── helpers ─────────────────────────────────────────────────────────

  defp tag_list(%{tags: tags}) when is_list(tags), do: tags
  defp tag_list(_), do: []

  defp status_label(:draft), do: "Draft"
  defp status_label(:filed), do: "Filed"
  defp status_label(:archived), do: "Archived"
  defp status_label(other), do: to_string(other)

  defp drawer_short(:ANT), do: "Dr. 01 Antiquity"
  defp drawer_short(:CLA), do: "Dr. 02 Classical"
  defp drawer_short(:MED), do: "Dr. 03 Medieval"
  defp drawer_short(:REN), do: "Dr. 04 Renaissance"
  defp drawer_short(:EAR), do: "Dr. 05 Early Modern"
  defp drawer_short(:MOD), do: "Dr. 06 Modern"
  defp drawer_short(:CON), do: "Dr. 07 Contemporary"
  defp drawer_short(other), do: to_string(other)

  defp pin_year(%{date_token: token}) do
    parse_date_token_year(token)
  end

  defp pin_year(_), do: nil

  # Provenance contract — see spec §7.2 (offsets) and Capture schema.
  # When a capture has a parent message, the link targets the message
  # anchor (`#message-<id>`) on the source conversation. We render the
  # selection bounds when the capture was `:selection`-scoped so the
  # reviewer can confirm offsets at Gate F.1.
  defp provenance(%{capture: %Ash.NotLoaded{}}), do: nil
  defp provenance(%{capture: nil}), do: nil

  defp provenance(%{capture: capture}) when is_map(capture) do
    conv_id = Map.get(capture, :conversation_id)
    msg_id = Map.get(capture, :message_id)
    build_provenance(capture, conv_id, msg_id)
  end

  defp provenance(_), do: nil

  defp build_provenance(_capture, nil, _msg_id), do: nil

  defp build_provenance(capture, conv_id, msg_id) do
    %{
      label: provenance_label(capture),
      scope_note: scope_note(capture),
      path: provenance_path(conv_id, msg_id)
    }
  end

  defp provenance_label(%{conversation: %{title: t}}) when is_binary(t) and t != "",
    do: "your conversation: " <> t

  defp provenance_label(_), do: "your conversation"

  defp provenance_path(conv_id, nil), do: "/conversations/#{conv_id}"
  defp provenance_path(conv_id, msg_id), do: "/conversations/#{conv_id}#message-#{msg_id}"

  defp scope_note(%{scope: :whole}), do: "whole response"

  defp scope_note(%{scope: :selection, selection_start: s, selection_end: e})
       when is_integer(s) and is_integer(e),
       do: "selection #{s}–#{e}"

  defp scope_note(%{scope: :selection}), do: "selection"
  defp scope_note(_), do: nil

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d %b %y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d %b %y")
  defp format_date(_), do: ""
end
