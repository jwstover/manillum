defmodule ManillumWeb.ConversationsLive do
  use Elixir.ManillumWeb, :live_view

  import ManillumWeb.ManillumComponents

  @actor_required? true
  @chat_ui_tools AshAi.ChatUI.Tools

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <div class="conversation">
      <.topbar active="conversations" meta={@topbar_meta}>
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
      <.era_band events={@mentions} />

      <div class="conversation__body">
        <aside class="conversation__rail">
          <div class="conversation__rail-head">
            <.meta_label tone={:oxblood}>Your Conversations</.meta_label>
            <.btn variant={:ghost} size={:sm} href={~p"/conversations"}>
              + new
            </.btn>
          </div>
          <p :if={not @has_conversations} class="conversation__rail-empty">
            no conversations yet
          </p>
          <ul class="conversation__rail-list" id="conversations-list" phx-update="stream">
            <li
              :for={{dom_id, conversation} <- @streams.conversations}
              id={dom_id}
              class={[
                "conversation__rail-item",
                @conversation && @conversation.id == conversation.id && "is-active"
              ]}
            >
              <.link
                navigate={~p"/conversations/#{conversation.id}"}
                class="conversation__rail-link"
              >
                <span class="conversation__rail-qry">
                  № {pad_qry(conversation.query_number)}
                </span>
                <span class="conversation__rail-ago">
                  {rail_ago(conversation)}
                </span>
                <span class="conversation__rail-title">
                  {rail_title(conversation.title)}
                </span>
              </.link>
            </li>
          </ul>
        </aside>

        <main class="conversation__main">
          <.convo_header
            :if={@conversation}
            query_number={@conversation.query_number}
            title={@conversation.title}
            exchanges={@exchange_count}
            opened_at={@conversation.inserted_at}
          />

          <.flash kind={:info} flash={@flash} />
          <.flash kind={:error} flash={@flash} />
          <.toast
            :if={Phoenix.Flash.get(@flash, :warning)}
            kind={:warn}
            title={Phoenix.Flash.get(@flash, :warning)}
          />

          <div
            id="message-container"
            phx-update="stream"
            phx-hook=".ConversationScroll"
            class="conversation__thread"
          >
            <script :type={Phoenix.LiveView.ColocatedHook} name=".ConversationScroll">
              // Toggle `is-scrolled` on the outer `.conversation` element
              // when the thread has been scrolled away from its resting
              // position (newest message at the bottom edge). Used by
              // `assets/css/components/conversation.css` to compact the era
              // band and convo header while the user reads older messages.
              //
              // The thread is `flex-direction: column-reverse`, so the
              // resting position reports `scrollTop ≈ 0` in Chrome/Safari
              // and the scrollTop becomes negative (or positive on Firefox)
              // as the user moves away from it. `Math.abs(scrollTop)` is
              // the browser-agnostic "distance from resting" probe.
              //
              // Two guardrails keep the toggle stable while the chrome's
              // CSS transition reflows the thread:
              //
              // 1. Hysteresis with absorption-aware entry threshold. When
              //    `is-scrolled` is added the convo header collapses,
              //    `.conversation__main`'s flex children reflow, the
              //    thread (flex: 1, column-reverse) grows by the convo
              //    header's full height (~84px), and scrollTop swings
              //    sharply toward 0. A single threshold drops back below
              //    the boundary mid-transition and the chrome flickers
              //    open/closed for a few cycles before damping out. The
              //    fix is a hysteresis dead-zone the absorption can't
              //    cross: pick `ENTER_THRESHOLD` > collapsed-element-
              //    height + `EXIT_THRESHOLD` so the post-absorption
              //    scrollTop always lands in the "stay compact" zone.
              //    For an ~84px convo header, ENTER 120 / EXIT 24 means
              //    a 120px scroll absorbs to ~-36, well outside the 24px
              //    exit boundary. Smaller scrolls don't trigger compact
              //    at all.
              //
              // 2. Toggle lock + post-lock recheck. After any class flip
              //    we ignore scroll events for the duration of the CSS
              //    transition (~260ms) so layout churn during the
              //    transition can't fire another flip. After the lock
              //    lifts we re-evaluate once — if no scroll events have
              //    fired since (scrollTop landed at rest mid-lock), this
              //    catches it; otherwise normal scroll handling resumes.
              const ENTER_THRESHOLD = 120;
              const EXIT_THRESHOLD = 24;
              const TOGGLE_LOCK_MS = 260;

              export default {
                mounted() {
                  this.root = this.el.closest(".conversation");
                  this.lockedUntil = 0;
                  this.recheckTimer = null;
                  this.onScroll = () => {
                    if (!this.root) return;
                    if (performance.now() < this.lockedUntil) return;
                    const distance = Math.abs(this.el.scrollTop);
                    const isScrolled = this.root.classList.contains("is-scrolled");
                    const next = isScrolled
                      ? distance > EXIT_THRESHOLD
                      : distance > ENTER_THRESHOLD;
                    if (next !== isScrolled) {
                      this.root.classList.toggle("is-scrolled", next);
                      this.lockedUntil = performance.now() + TOGGLE_LOCK_MS;
                      // After the lock lifts, re-evaluate once. If the
                      // transition's layout shift left scrollTop in a
                      // position that should trigger another toggle (e.g.
                      // the user briefly scrolled into the entry zone but
                      // settled back at rest), this catches it. Without
                      // the recheck, no further scroll events fire to wake
                      // the listener and the chrome can stay in the wrong
                      // state at the final scroll position.
                      clearTimeout(this.recheckTimer);
                      this.recheckTimer = setTimeout(this.onScroll, TOGGLE_LOCK_MS + 16);
                    }
                  };
                  this.el.addEventListener("scroll", this.onScroll, { passive: true });
                  // Re-evaluate on mount: a navigation between conversations
                  // can land the thread at a non-zero scroll position before
                  // any user input fires the listener.
                  this.onScroll();
                },
                destroyed() {
                  this.el.removeEventListener("scroll", this.onScroll);
                  clearTimeout(this.recheckTimer);
                  if (this.root) this.root.classList.remove("is-scrolled");
                },
              };
            </script>
            <%= for {dom_id, message} <- @streams.messages do %>
              <.message
                id={dom_id}
                role={message_role_atom(message)}
                timestamp={format_msg_clock(message)}
              >
                {to_markdown(message.content || "")}

                <div :if={tool_calls(message) != []} class="message__tool_calls">
                  <span :for={tool_call <- tool_calls(message)} class="message__tool_call">
                    tool: {tool_call.name}<span :if={tool_call.arguments != %{}}>
                    ({tool_call.arguments_preview})</span>
                  </span>
                </div>

                <div :if={tool_results(message) != []} class="message__tool_results">
                  <div
                    :for={tool_result <- tool_results(message)}
                    class={[
                      "message__tool_result",
                      tool_result.is_error && "message__tool_result--error"
                    ]}
                  >
                    <strong>
                      {if tool_result.is_error, do: "tool_error", else: "tool_result"}
                    </strong>
                    <span :if={tool_result.name}> ({tool_result.name})</span>: {tool_result.content_preview}
                  </div>
                </div>
              </.message>
            <% end %>
          </div>

          <.composing_indicator :if={@agent_responding} />

          <.composer
            :if={@message_form}
            form={@message_form}
            phx_change="validate_message"
            phx_submit="send_message"
          />
        </main>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket = assign_new(socket, :current_user, fn -> nil end)

    if socket.assigns.current_user do
      ManillumWeb.Endpoint.subscribe("chat:conversations:#{socket.assigns.current_user.id}")
    end

    conversations =
      if @actor_required? && is_nil(socket.assigns.current_user) do
        []
      else
        Manillum.Conversations.my_conversations!(actor: socket.assigns.current_user)
      end

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> stream(:conversations, conversations)
      |> assign(:has_conversations, conversations != [])
      |> assign(:agent_responding, false)
      |> assign(:tool_data_warning_shown?, false)
      |> assign(:conversation, nil)
      |> assign(:exchange_count, 0)
      |> assign(:topbar_meta, topbar_meta(conversations))
      |> assign(:message_form, nil)
      |> assign(:mentions, [])
      |> stream_configure(:messages, dom_id: &"message-#{&1.id}")

    {:ok, socket}
  end

  def handle_params(%{"conversation_id" => conversation_id}, _, socket) do
    if @actor_required? && is_nil(socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:error, "You must sign in to access conversations")
       |> push_navigate(to: ~p"/conversations")}
    else
      conversation =
        Manillum.Conversations.get_conversation!(conversation_id,
          actor: socket.assigns.current_user
        )

      messages = Manillum.Conversations.message_history!(conversation.id, stream?: true)

      mentions =
        Manillum.Conversations.list_mentions!(conversation.id, actor: socket.assigns.current_user)

      cond do
        socket.assigns[:conversation] && socket.assigns[:conversation].id == conversation.id ->
          :ok

        socket.assigns[:conversation] ->
          ManillumWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
          ManillumWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")

        true ->
          ManillumWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")
      end

      socket
      |> maybe_warn_tool_data(messages)
      |> assign(:conversation, conversation)
      |> assign(:exchange_count, count_exchanges(messages))
      |> assign(:agent_responding, agent_response_pending?(messages))
      |> assign(:mentions, mentions)
      |> stream(:messages, messages, reset: true)
      |> assign_message_form()
      |> then(&{:noreply, &1})
    end
  end

  def handle_params(_, _, socket) do
    if socket.assigns[:conversation] do
      ManillumWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
    end

    socket
    |> assign(:conversation, nil)
    |> assign(:exchange_count, 0)
    |> assign(:agent_responding, false)
    |> assign(:mentions, [])
    |> stream(:messages, [], reset: true)
    |> assign_message_form()
    |> then(&{:noreply, &1})
  end

  def handle_event("validate_message", %{"form" => params}, socket) do
    {:noreply,
     assign(socket, :message_form, AshPhoenix.Form.validate(socket.assigns.message_form, params))}
  end

  def handle_event("send_message", %{"form" => params}, socket) do
    if @actor_required? && is_nil(socket.assigns.current_user) do
      {:noreply, put_flash(socket, :error, "You must sign in to send messages")}
    else
      case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
        {:ok, message} ->
          if socket.assigns.conversation do
            socket
            |> assign(:agent_responding, true)
            |> assign_message_form()
            |> stream_insert(:messages, message, at: 0)
            |> then(&{:noreply, &1})
          else
            {:noreply,
             socket
             |> push_navigate(to: ~p"/conversations/#{message.conversation_id}")}
          end

        {:error, form} ->
          {:noreply, assign(socket, :message_form, form)}
      end
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:messages:" <> conversation_id,
          payload: %{kind: :mention_placed} = mention
        },
        socket
      ) do
    if socket.assigns.conversation && socket.assigns.conversation.id == conversation_id do
      {:noreply, update(socket, :mentions, &upsert_mention(&1, mention))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:messages:" <> conversation_id,
          payload: message
        },
        socket
      ) do
    if socket.assigns.conversation && socket.assigns.conversation.id == conversation_id do
      socket =
        socket
        |> maybe_warn_tool_data(message)
        |> stream_insert(:messages, message, at: 0)
        |> update_agent_responding(message)
        |> maybe_bump_exchanges(message)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:conversations:" <> _,
          payload: conversation
        },
        socket
      ) do
    socket =
      if socket.assigns.conversation && socket.assigns.conversation.id == conversation.id do
        assign(socket, :conversation, conversation)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:has_conversations, true)
     |> stream_insert(:conversations, conversation)}
  end

  defp assign_message_form(socket) do
    form =
      if socket.assigns.conversation do
        Manillum.Conversations.form_to_create_message(
          actor: socket.assigns.current_user,
          private_arguments: %{conversation_id: socket.assigns.conversation.id}
        )
        |> to_form()
      else
        Manillum.Conversations.form_to_create_message(actor: socket.assigns.current_user)
        |> to_form()
      end

    assign(socket, :message_form, form)
  end

  defp tool_calls(message), do: safe_extract(message).tool_calls

  defp tool_results(message), do: safe_extract(message).tool_results

  defp safe_extract(message) do
    case @chat_ui_tools.extract(message) do
      {:ok, extracted} ->
        extracted

      {:error, _} ->
        %{tool_calls: [], tool_results: []}
    end
  end

  defp maybe_warn_tool_data(socket, messages) when is_list(messages) do
    Enum.reduce(messages, socket, fn message, acc ->
      maybe_warn_tool_data(acc, message)
    end)
  end

  defp maybe_warn_tool_data(socket, message) do
    if assistant_message?(message) do
      case @chat_ui_tools.extract(message) do
        {:ok, _} ->
          socket

        {:error, _} ->
          maybe_put_tool_data_warning(socket)
      end
    else
      socket
    end
  end

  defp maybe_put_tool_data_warning(socket) do
    if socket.assigns[:tool_data_warning_shown?] do
      socket
    else
      socket
      |> put_flash(:warning, "Some tool call data could not be displayed.")
      |> assign(:tool_data_warning_shown?, true)
    end
  end

  defp message_role(%{role: role}), do: role
  defp message_role(%{"role" => role}), do: role
  defp message_role(_), do: nil

  defp message_complete?(%{complete: complete}), do: complete in [true, "true"]
  defp message_complete?(%{"complete" => complete}), do: complete in [true, "true"]
  defp message_complete?(_), do: false

  defp user_message?(message), do: message_role(message) in [:user, "user"]
  defp assistant_message?(message), do: message_role(message) in [:assistant, "assistant"]

  defp message_role_atom(message) do
    case message_role(message) do
      :assistant -> :assistant
      "assistant" -> :assistant
      _ -> :user
    end
  end

  defp update_agent_responding(socket, message) do
    cond do
      user_message?(message) ->
        assign(socket, :agent_responding, true)

      assistant_message?(message) ->
        assign(socket, :agent_responding, !message_complete?(message))

      true ->
        socket
    end
  end

  defp agent_response_pending?(messages) do
    case Enum.find(messages, fn message ->
           user_message?(message) or assistant_message?(message)
         end) do
      nil -> false
      message -> user_message?(message) || !message_complete?(message)
    end
  end

  defp pad_qry(n) when is_integer(n) and n >= 0 do
    n |> Integer.to_string() |> String.pad_leading(4, "0")
  end

  defp pad_qry(_), do: "----"

  defp user_display(%{email: email}), do: to_string(email)
  defp user_display(_), do: ""

  defp rail_title(nil), do: "Untitled conversation"
  defp rail_title(""), do: "Untitled conversation"
  defp rail_title(title) when is_binary(title), do: title

  defp rail_ago(%{updated_at: %DateTime{} = dt}), do: format_ago(DateTime.utc_now(), dt)

  defp rail_ago(%{updated_at: %NaiveDateTime{} = dt}),
    do: format_ago(NaiveDateTime.utc_now(), dt)

  defp rail_ago(_), do: ""

  defp format_ago(now, then) do
    seconds = abs_diff_seconds(now, then)

    cond do
      seconds < 60 -> "now"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h"
      seconds < 604_800 -> "#{div(seconds, 86_400)}d"
      true -> "#{div(seconds, 604_800)}w"
    end
  end

  defp abs_diff_seconds(%DateTime{} = a, %DateTime{} = b),
    do: abs(DateTime.diff(a, b, :second))

  defp abs_diff_seconds(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: abs(NaiveDateTime.diff(a, b, :second))

  # Upsert a mention into the assigns list. Broadcasts (and the LiveView
  # tests) deliver maps keyed by atoms; the initial `list_mentions!` load
  # delivers `%Mention{}` structs. The era_band component reads each event
  # via `Map.get/2`, so both shapes coexist — but we still need to match
  # them up by id so a re-broadcast doesn't double-render.
  defp upsert_mention(mentions, %{id: id} = mention) when is_list(mentions) do
    case Enum.split_with(mentions, fn existing -> mention_id(existing) == id end) do
      {[], []} -> [mention]
      {[], rest} -> [mention | rest]
      {[_ | _], rest} -> [mention | rest]
    end
  end

  defp mention_id(%{id: id}), do: id
  defp mention_id(_), do: nil

  defp count_exchanges(messages) do
    Enum.count(messages, &user_message?/1)
  end

  defp maybe_bump_exchanges(socket, message) do
    if user_message?(message) do
      assign(socket, :exchange_count, socket.assigns.exchange_count + 1)
    else
      socket
    end
  end

  defp topbar_meta([]), do: nil

  defp topbar_meta(conversations) do
    "#{length(conversations)} conversations"
  end

  # The PubSub broadcast for messages publishes a plain map (no
  # inserted_at field) — return nil there so the speaker label stays
  # stable until the full record is fetched.
  defp format_msg_clock(%{inserted_at: %DateTime{} = dt}) do
    "#{pad2(dt.hour)}:#{pad2(dt.minute)}"
  end

  defp format_msg_clock(%{inserted_at: %NaiveDateTime{} = dt}) do
    "#{pad2(dt.hour)}:#{pad2(dt.minute)}"
  end

  defp format_msg_clock(_), do: nil

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: "#{n}"

  defp to_markdown(text) do
    MDEx.to_html(text,
      extension: [
        strikethrough: true,
        tagfilter: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        shortcodes: true
      ],
      parse: [
        smart: true,
        relaxed_tasklist_matching: true,
        relaxed_autolinks: true
      ],
      render: [
        github_pre_lang: true,
        unsafe: true
      ],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> case do
      {:ok, html} ->
        Phoenix.HTML.raw(html)

      {:error, _} ->
        text
    end
  end
end
