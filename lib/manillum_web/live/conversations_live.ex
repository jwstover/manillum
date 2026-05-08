defmodule ManillumWeb.ConversationsLive do
  use Elixir.ManillumWeb, :live_view

  require Logger

  import ManillumWeb.ManillumComponents

  @actor_required? true
  @chat_ui_tools AshAi.ChatUI.Tools

  on_mount {ManillumWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <div class="conversation">
      <ManillumWeb.Layouts.flash_group flash={@flash}>
        <ManillumWeb.CoreComponents.flash
          :if={@undo_state}
          id="undo-toast"
          kind={:ok}
          kicker="● FILED"
          title={undo_title(@undo_state)}
          show_progress={true}
        >
          <:actions>
            <button type="button" phx-click="undo_file">undo</button>
          </:actions>
        </ManillumWeb.CoreComponents.flash>
      </ManillumWeb.Layouts.flash_group>
      <.topbar active="conversations">
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

          <button
            id="filing-selection-btn"
            type="button"
            class="message__file_selection"
            phx-hook=".FilingSelection"
            hidden
          >
            + FILE SELECTION
          </button>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".FilingSelection">
            // Floating "+ FILE SELECTION" button. Watches document
            // selection events; when the user selects text inside the
            // body of a complete assistant message, positions itself
            // near the selection's bottom edge and becomes visible.
            // Clicking it pushes a `file` event with scope=selection
            // plus the selected text + the source message/conversation
            // ids.
            //
            // The pushEvent path bypasses phx-click because phx-value-*
            // can't be rebuilt cheaply on every selection change; the
            // hook keeps the active state in a closure and dispatches
            // directly when the user clicks.
            export default {
              mounted() {
                this.active = null; // {text, message_id, conversation_id}
                this.onSelect = () => {
                  const sel = window.getSelection();
                  if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
                    this.hide();
                    return;
                  }
                  const range = sel.getRangeAt(0);
                  // Selection must be anchored inside the body of a
                  // complete assistant message. Anything else (composer
                  // text, sidebar, header chrome) is ignored.
                  const messageBody =
                    range.startContainer.nodeType === Node.ELEMENT_NODE
                      ? range.startContainer.closest(".message__body")
                      : range.startContainer.parentElement?.closest(
                          ".message__body",
                        );
                  if (!messageBody) {
                    this.hide();
                    return;
                  }
                  const article = messageBody.closest("article.message");
                  if (!article || !article.classList.contains("message--assistant")) {
                    this.hide();
                    return;
                  }
                  const text = sel.toString();
                  if (!text || text.trim() === "") {
                    this.hide();
                    return;
                  }
                  const messageId = article.dataset.messageId;
                  const conversationId = article.dataset.conversationId;
                  if (!messageId || !conversationId) {
                    this.hide();
                    return;
                  }
                  this.active = {
                    text,
                    message_id: messageId,
                    conversation_id: conversationId,
                  };
                  // Position near the selection's end. getBoundingClientRect
                  // is the union of the selection's rects; fall back to the
                  // last range rect for multi-line selections.
                  const rects = range.getClientRects();
                  const r = rects.length > 0 ? rects[rects.length - 1] : range.getBoundingClientRect();
                  this.el.style.top = `${window.scrollY + r.bottom + 6}px`;
                  this.el.style.left = `${window.scrollX + r.right + 6}px`;
                  this.el.hidden = false;
                };
                this.onClick = (e) => {
                  // Don't dismiss on clicking the button itself.
                  if (this.el.contains(e.target)) return;
                  this.hide();
                };
                this.onButtonClick = (e) => {
                  e.preventDefault();
                  if (!this.active) return;
                  this.pushEvent("file", {
                    scope: "selection",
                    message_id: this.active.message_id,
                    conversation_id: this.active.conversation_id,
                    text: this.active.text,
                  });
                  // Clear the selection + button so a second click doesn't
                  // re-fire and the user gets visual confirmation.
                  window.getSelection()?.removeAllRanges();
                  this.hide();
                };
                this.hide = () => {
                  this.active = null;
                  this.el.hidden = true;
                };
                document.addEventListener("selectionchange", this.onSelect);
                document.addEventListener("mousedown", this.onClick);
                this.el.addEventListener("click", this.onButtonClick);
              },
              destroyed() {
                document.removeEventListener("selectionchange", this.onSelect);
                document.removeEventListener("mousedown", this.onClick);
                this.el.removeEventListener("click", this.onButtonClick);
              },
            };
          </script>
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
              //
              // 3. Suppress scroll-anchoring during the transition.
              //    Default `overflow-anchor: auto` re-pins scrollTop on
              //    every reflow frame as the convo_header transitions
              //    from 12rem → 0; that per-frame numerical shift fights
              //    the user's active scroll input and shows up as a
              //    visible stutter. We flip `overflow-anchor: none` for
              //    the toggle-lock window so scrollTop is left alone —
              //    column-reverse already anchors items to the visual
              //    bottom, and the freed space at the top simply reveals
              //    more older messages without disturbing what's on
              //    screen. Anchoring is restored after the transition so
              //    streaming new messages while scrolled up still keeps
              //    the user's view stable.
              const ENTER_THRESHOLD = 120;
              const EXIT_THRESHOLD = 24;
              const TOGGLE_LOCK_MS = 260;

              export default {
                mounted() {
                  this.root = this.el.closest(".conversation");
                  this.lockedUntil = 0;
                  this.recheckTimer = null;
                  this.anchorRestoreTimer = null;
                  this.onScroll = () => {
                    if (!this.root) return;
                    if (performance.now() < this.lockedUntil) return;
                    const distance = Math.abs(this.el.scrollTop);
                    const isScrolled = this.root.classList.contains("is-scrolled");
                    const next = isScrolled
                      ? distance > EXIT_THRESHOLD
                      : distance > ENTER_THRESHOLD;
                    if (next !== isScrolled) {
                      // Suppress scroll-anchoring for the transition so
                      // the browser doesn't fight the user's scroll input
                      // each frame as the convo_header collapses.
                      this.el.style.overflowAnchor = "none";
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
                      // Restore anchoring once the transition has
                      // settled so streaming inserts (LiveView `at: 0`)
                      // continue to keep the user's view stable.
                      clearTimeout(this.anchorRestoreTimer);
                      this.anchorRestoreTimer = setTimeout(() => {
                        this.el.style.overflowAnchor = "";
                      }, TOGGLE_LOCK_MS + 16);
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
                  clearTimeout(this.anchorRestoreTimer);
                  this.el.style.overflowAnchor = "";
                  if (this.root) this.root.classList.remove("is-scrolled");
                },
              };
            </script>
            <%= for {dom_id, message} <- @streams.messages do %>
              <.message
                id={dom_id}
                role={message_role_atom(message)}
                timestamp={format_msg_clock(message)}
                data-message-id={message_field(message, :id)}
                data-conversation-id={message_field(message, :conversation_id)}
              >
                {to_markdown(message.content || "")}

                <div
                  :if={assistant_message?(message) and message_complete?(message)}
                  class="message__file_all"
                >
                  <button
                    type="button"
                    class="message__file_all_btn"
                    phx-click="file"
                    phx-value-scope="whole"
                    phx-value-message-id={message_field(message, :id)}
                    phx-value-conversation-id={message_field(message, :conversation_id)}
                  >
                    + FILE ALL
                  </button>
                </div>

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

        <.live_component
          :if={@current_user}
          module={ManillumWeb.FilingTrayComponent}
          id="filing-tray"
          actor={@current_user}
        />
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket = assign_new(socket, :current_user, fn -> nil end)

    if socket.assigns.current_user do
      user_id = socket.assigns.current_user.id
      ManillumWeb.Endpoint.subscribe("chat:conversations:#{user_id}")
      # Cataloging broadcasts (per spec §7.3) — surface :cards_drafted /
      # :cards_drafting_failed as toasts here. The proper filing-tray
      # hand-off lands with Slice 10 (M-28); for now this is enough to
      # confirm Gate D.3's end-to-end "+ FILE → Capture → drafts" loop.
      Phoenix.PubSub.subscribe(Manillum.PubSub, "user:#{user_id}:cataloging")
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
      |> assign(:message_form, nil)
      |> assign(:mentions, [])
      |> assign(:undo_state, nil)
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

  # +FILE ALL (scope: :whole) and +FILE SELECTION (scope: :selection)
  # both dispatch here. Resolve source_text from the scope, hand off to
  # Manillum.Archive.submit/2, and walk away — the Capture's AshOban
  # trigger drives the rest of the cataloging pipeline asynchronously
  # per spec §5 Stream C / §7.3.
  def handle_event("file", params, socket) do
    user = socket.assigns.current_user

    cond do
      is_nil(user) ->
        Logger.warning("[file] rejected — no current_user")
        {:noreply, put_flash(socket, :error, "You must sign in to file")}

      true ->
        case build_capture_attrs(params, user) do
          {:ok, attrs} ->
            Logger.debug(
              "[file] submitting capture user_id=#{user.id} scope=#{attrs.scope} message_id=#{attrs.message_id} text_len=#{String.length(attrs.source_text || "")}"
            )

            case Manillum.Archive.submit(attrs, actor: user) do
              {:ok, capture} ->
                Logger.info(
                  "[file] capture submitted id=#{capture.id} scope=#{capture.scope} user_id=#{user.id}"
                )

                send_update(ManillumWeb.FilingTrayComponent,
                  id: "filing-tray",
                  action: {:capture_submitted, %{capture_id: capture.id}}
                )

                {:noreply, put_flash(socket, :info, "Filing — drafts will appear shortly")}

              {:error, err} ->
                Logger.error(
                  "[file] Manillum.Archive.submit failed user_id=#{user.id} params=#{inspect(params)} error=#{inspect(err, pretty: true, limit: :infinity)}"
                )

                {:noreply, put_flash(socket, :error, "Couldn't start filing. Try again.")}
            end

          {:error, reason} ->
            Logger.warning(
              "[file] rejected — invalid params user_id=#{user.id} reason=#{reason} params=#{inspect(params)}"
            )

            {:noreply, put_flash(socket, :error, "Couldn't file: #{reason}")}
        end
    end
  end

  # Undo a recent file action — calls `Archive.unfile_card/2` and pushes
  # the now-back-to-:draft card to the filing tray. Window enforced
  # by the parent's `:undo_state` assign (cleared after 10s by
  # `{:undo_expire, id}` from `handle_info`).
  def handle_event("undo_file", _params, socket) do
    user = socket.assigns.current_user

    case socket.assigns.undo_state do
      %{kind: :single, card_id: id} when not is_nil(user) ->
        case undo_one(id, user) do
          {:ok, drafted} ->
            send_update(ManillumWeb.FilingTrayComponent,
              id: "filing-tray",
              action: {:restore_draft, drafted}
            )

            {:noreply, assign(socket, :undo_state, nil)}

          {:error, err} ->
            Logger.error("[undo_file] failed id=#{id} error=#{inspect(err)}")

            {:noreply,
             socket
             |> assign(:undo_state, nil)
             |> put_flash(:error, "Couldn't undo. The card is filed.")}
        end

      %{kind: :batch, card_ids: ids} when not is_nil(user) ->
        Enum.each(ids, fn id ->
          case undo_one(id, user) do
            {:ok, drafted} ->
              send_update(ManillumWeb.FilingTrayComponent,
                id: "filing-tray",
                action: {:restore_draft, drafted}
              )

            {:error, err} ->
              Logger.error("[undo_file batch] failed id=#{id} error=#{inspect(err)}")
          end
        end)

        {:noreply, assign(socket, :undo_state, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  defp undo_one(id, user) do
    with {:ok, card} <-
           Ash.get(Manillum.Archive.Card, id, actor: user, load: [:call_number]),
         {:ok, drafted} <- Manillum.Archive.unfile_card(card, actor: user) do
      # Reload to get the freshly-loaded :call_number calc on the
      # demoted card before handing it to the tray.
      {:ok, Ash.load!(drafted, [:capture, :call_number], actor: user)}
    end
  end

  defp build_capture_attrs(%{"scope" => scope} = params, user) do
    message_id = params["message_id"] || params["message-id"]
    conversation_id = params["conversation_id"] || params["conversation-id"]

    with true <- is_binary(message_id) || {:error, "missing message_id"},
         true <- is_binary(conversation_id) || {:error, "missing conversation_id"},
         {:ok, source_text} <- resolve_source(scope, message_id, params) do
      {:ok,
       %{
         user_id: user.id,
         conversation_id: conversation_id,
         message_id: message_id,
         scope: String.to_existing_atom(scope),
         source_text: source_text
       }}
    else
      {:error, _} = err -> err
      false -> {:error, "missing identifiers"}
    end
  end

  defp build_capture_attrs(_params, _user), do: {:error, "missing scope"}

  defp resolve_source("whole", message_id, _params) do
    case Manillum.Conversations.Message |> Ash.get(message_id, authorize?: false) do
      {:ok, %{content: content}} ->
        {:ok, content || ""}

      {:error, err} ->
        Logger.warning(
          "[file] resolve_source(whole) — message lookup failed message_id=#{message_id} error=#{inspect(err)}"
        )

        {:error, "message not found"}
    end
  end

  defp resolve_source("selection", _message_id, params) do
    text = params["text"] || ""

    if String.trim(text) == "" do
      Logger.warning("[file] resolve_source(selection) — empty selection text")
      {:error, "empty selection"}
    else
      {:ok, text}
    end
  end

  defp resolve_source(scope, _message_id, _params) do
    Logger.warning("[file] resolve_source — invalid scope=#{inspect(scope)}")
    {:error, "invalid scope"}
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
     |> stream_insert(:conversations, conversation, at: 0)}
  end

  # Cataloging broadcasts (spec §7.3, topic "user:#{user_id}:cataloging").
  # Forward to the filing tray (Slice 10A / M-28); the tray owns the
  # rendered state from here.
  def handle_info({:cards_drafted, _} = msg, socket) do
    send_update(ManillumWeb.FilingTrayComponent, id: "filing-tray", action: msg)
    {:noreply, socket}
  end

  def handle_info({:cards_drafting_failed, payload} = msg, socket) do
    Logger.error(
      "[cataloging] failed payload=#{inspect(payload, pretty: true, limit: :infinity)}"
    )

    send_update(ManillumWeb.FilingTrayComponent, id: "filing-tray", action: msg)
    {:noreply, socket}
  end

  # File-action lifecycle (Slice 10B / M-28). Decision 2026-05-07 option B:
  # `Card.:file` runs immediately; the undo path lives here in the parent LV
  # with a 10-second grace window, after which the action becomes irreversible.
  #
  # Sequence:
  #   1. tray's `handle_event("file_card", ...)` calls `Archive.file_card/2`
  #      and sends us `{:filed_card_for_undo, payload}`.
  #   2. We schedule `{:remove_filed_dom, dom_id}` 1100ms out so the
  #      tray's stamp-impression + slide-out keyframes can complete before
  #      `stream_delete` removes the article.
  #   3. We schedule `{:undo_expire, card_id}` 10s out and assign
  #      `:undo_state` so the undo toast renders.
  #   4. Click "undo" → `handle_event("undo_file", ...)` → `Archive.unfile_card/2`
  #      → restore the card to the tray via `send_update`.
  def handle_info({:filed_card_for_undo, payload}, socket) do
    %{card_id: id, dom_id: dom_id, call_number: cn} = payload

    Process.send_after(self(), {:remove_filed_dom, dom_id, id}, 1100)
    Process.send_after(self(), {:undo_expire, id}, 10_000)

    {:noreply, assign(socket, :undo_state, %{kind: :single, card_id: id, call_number: cn})}
  end

  # Bulk file action (M-63). Same shape as `:filed_card_for_undo` but
  # carries a list of files. Schedules per-card removals on the same
  # 1100ms beat so each article finishes its FILED-stamp + slide-out
  # animation before its `stream_delete` fires. A single batch
  # `:undo_expire` clears `:undo_state` after 10s.
  def handle_info({:filed_all_for_undo, %{filed: filed}}, socket) do
    Enum.each(filed, fn %{dom_id: dom_id, card_id: id} ->
      Process.send_after(self(), {:remove_filed_dom, dom_id, id}, 1100)
    end)

    card_ids = Enum.map(filed, & &1.card_id)
    Process.send_after(self(), {:undo_expire_batch, card_ids}, 10_000)

    sample = filed |> hd() |> Map.get(:call_number)

    undo_state = %{
      kind: :batch,
      card_ids: card_ids,
      count: length(filed),
      sample_call_number: sample
    }

    {:noreply, assign(socket, :undo_state, undo_state)}
  end

  def handle_info({:remove_filed_dom, dom_id, card_id}, socket) do
    # If the user undid the file action within the 1100ms animation
    # window, the card is back to `:draft` and re-inserted into the
    # tray. Don't remove it from the tray in that case — the user
    # changed their mind. We confirm by reading the persisted status
    # rather than introspecting in-memory undo_state, since the undo
    # path may have already cleared it.
    actor = socket.assigns.current_user

    case actor && Ash.get(Manillum.Archive.Card, card_id, actor: actor) do
      {:ok, %{status: :filed}} ->
        send_update(ManillumWeb.FilingTrayComponent,
          id: "filing-tray",
          action: {:remove_filed, dom_id}
        )

      _ ->
        :noop
    end

    {:noreply, socket}
  end

  def handle_info({:undo_expire, card_id}, socket) do
    case socket.assigns.undo_state do
      %{kind: :single, card_id: ^card_id} -> {:noreply, assign(socket, :undo_state, nil)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:undo_expire_batch, card_ids}, socket) do
    case socket.assigns.undo_state do
      %{kind: :batch, card_ids: stored} ->
        if MapSet.new(stored) == MapSet.new(card_ids) do
          {:noreply, assign(socket, :undo_state, nil)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:file_card_failed, _id}, socket) do
    {:noreply, put_flash(socket, :error, "Couldn't file that draft. Try again.")}
  end

  def handle_info({:edit_save_failed, _id, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
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
      |> put_flash(:warn, "Some tool call data could not be displayed.")
      |> assign(:tool_data_warning_shown?, true)
    end
  end

  defp message_role(%{role: role}), do: role
  defp message_role(%{"role" => role}), do: role
  defp message_role(_), do: nil

  defp message_complete?(%{complete: complete}), do: complete in [true, "true"]
  defp message_complete?(%{"complete" => complete}), do: complete in [true, "true"]
  defp message_complete?(_), do: false

  # Generic message-field access. The streams hold a mix of Ash structs
  # (full atom-keyed shape) and PubSub broadcast payloads (subset, atom
  # keys). Use this for any field on a message in the template so a
  # missing field never crashes the LV — log + return nil instead.
  defp message_field(message, key) when is_map(message) do
    case Map.fetch(message, key) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(message, Atom.to_string(key)) do
          {:ok, value} ->
            value

          :error ->
            Logger.warning(
              "[ConversationsLive] message_field/2 missing key=#{key} in message=#{inspect(message, limit: 5)}"
            )

            nil
        end
    end
  end

  defp message_field(_, _), do: nil

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

  defp undo_title(%{kind: :single, call_number: cn}), do: cn
  defp undo_title(%{kind: :batch, count: 1, sample_call_number: cn}), do: cn
  defp undo_title(%{kind: :batch, count: count}), do: "Filed #{count} cards"
  defp undo_title(%{call_number: cn}), do: cn

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
