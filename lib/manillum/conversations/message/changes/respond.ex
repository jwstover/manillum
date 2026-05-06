defmodule Manillum.Conversations.Message.Changes.Respond do
  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      message = changeset.data

      messages =
        Manillum.Conversations.Message
        |> Ash.Query.filter(conversation_id == ^message.conversation_id)
        |> Ash.Query.filter(id != ^message.id)
        |> Ash.Query.select([:content, :role, :tool_calls, :tool_results])
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(scope: context)
        |> Enum.concat([%{role: :user, content: message.content}])

      prompt_messages = [Context.system(system_prompt())] ++ message_chain(messages)

      new_message_id = Ash.UUIDv7.generate()

      # Pre-create the in-progress assistant message row so tools called
      # mid-stream can FK-reference it via `message_id`.
      #
      # Without this, tools that fire **before** the first content chunk
      # (Livy's `place_event_on_timeline` will sometimes lead the response
      # with a tool call) hit a FK violation on `mentions.message_id`,
      # because the assistant row isn't persisted until the content
      # branch of this reduce sees its first chunk. The pre-create lands
      # an empty row with `complete: false` that subsequent
      # `:upsert_response` calls update in place via `atomic_update`.
      Manillum.Conversations.Message
      |> Ash.Changeset.for_create(
        :upsert_response,
        %{
          id: new_message_id,
          response_to_id: message.id,
          conversation_id: message.conversation_id,
          content: ""
        },
        actor: %AshAi{}
      )
      |> Ash.create!()

      # Inject `current_conversation_id` / `current_message_id` into the
      # tool-loop's action context so tools that need to reference the
      # in-progress turn (e.g. `Mention.:place_event_on_timeline`) can pull
      # them from the changeset's context. Tools never trust the LLM to
      # supply these.
      #
      # Shape note: AshAi.ToolLoop's `context:` option is forwarded
      # verbatim to the tool action's `context:` opt — and from there into
      # `Ash.Changeset.for_create(..., context: ...)`, which lands at
      # `changeset.context`. So the keys here must be **flat** (not nested
      # under `:context`); the consumer (`SetConversationFromContext`)
      # reads `changeset.context.current_conversation_id` directly.
      # `actor` and `tenant` are passed separately to ToolLoop and don't
      # need to live in this map.
      loop_context = %{
        current_conversation_id: message.conversation_id,
        current_message_id: new_message_id
      }

      final_state =
        prompt_messages
        |> AshAi.ToolLoop.stream(
          otp_app: :manillum,
          tools: true,
          model: "anthropic:claude-sonnet-4-5",
          actor: context.actor,
          tenant: context.tenant,
          context: loop_context
        )
        |> Enum.reduce(%{content: "", tool_calls: [], tool_results: [], stream_error: nil}, fn
          {:content, content}, acc ->
            if content not in [nil, ""] do
              Manillum.Conversations.Message
              |> Ash.Changeset.for_create(
                :upsert_response,
                %{
                  id: new_message_id,
                  response_to_id: message.id,
                  conversation_id: message.conversation_id,
                  content: content
                },
                actor: %AshAi{}
              )
              |> Ash.create!()
            end

            %{acc | content: acc.content <> (content || "")}

          {:tool_call, tool_call}, acc ->
            %{acc | tool_calls: append_event(acc.tool_calls, tool_call)}

          {:tool_result, %{id: id, result: result}}, acc ->
            %{
              acc
              | tool_results: append_event(acc.tool_results, normalize_tool_result(id, result))
            }

          {:error, reason}, acc ->
            %{acc | stream_error: reason}

          {:done, _}, acc ->
            acc

          _, acc ->
            acc
        end)

      stream_error_text = stream_error_text(final_state.stream_error)

      final_content =
        cond do
          stream_error_text && String.trim(final_state.content || "") != "" ->
            final_state.content <> "\n\n" <> stream_error_text

          stream_error_text ->
            stream_error_text

          String.trim(final_state.content || "") == "" &&
              (final_state.tool_calls != [] || final_state.tool_results != []) ->
            "Completed tool call."

          true ->
            final_state.content
        end

      if final_state.stream_error ||
           final_state.tool_calls != [] ||
           final_state.tool_results != [] ||
           final_content != "" do
        Manillum.Conversations.Message
        |> Ash.Changeset.for_create(
          :upsert_response,
          %{
            id: new_message_id,
            response_to_id: message.id,
            conversation_id: message.conversation_id,
            complete: true,
            tool_calls: final_state.tool_calls,
            tool_results: final_state.tool_results,
            content: final_content
          },
          actor: %AshAi{}
        )
        |> Ash.create!()
      end

      changeset
    end)
  end

  defp system_prompt do
    """
    You are Livy, the user's history companion in Manillum — a personal
    history-learning app organized like a library card catalog. The user
    is talking with you to deepen their understanding of historical events,
    people, places, and ideas, and to file what they learn as cards in
    their archive.

    ## Voice

    History-curious. Precise about dates, names, and sources, and
    comfortable being explicit about uncertainty when the record is
    contested or thin ("around 1066", "by the late 4th c.", "traditionally
    dated to 753 BC"). Avoid the schoolbook tone — write like a quietly
    enthusiastic friend who happens to know a lot. Concise paragraphs;
    the user can always ask for more.

    ## Tools

    You have a `place_event_on_timeline` tool. Use it whenever the
    conversation establishes a specific dated historical event — battles,
    treaties, deaths, foundings, eruptions, voyages, publications. The
    user's era band shows your placements in real time, so this is how
    you make the conversation tangible.

    Rules:

    - Only place events tied to a known year. Skip allusions, periods
      ("the Renaissance"), and timeless concepts.
    - Provide as much date precision as you're confident in. Leave
      `month` and `day` nil rather than guessing — a year-only mention is
      fine. `day` requires `month`.
    - BC years use negative integers (44 BC = `-44`, 753 BC = `-753`,
      Battle of Hastings = `1066`).
    - You can call the tool multiple times in one turn for multiple
      events. Repeats of the same event in the same conversation are
      idempotent — safe to call again.

    Don't ask permission to call it; just call it when the criteria are
    met. Don't narrate the tool call ("I'll add that to your timeline...");
    the UI surfaces it on its own.
    """
  end

  defp message_chain(messages) do
    Enum.map(messages, fn
      %{role: :assistant, content: content} ->
        # Historical tool call replay can break provider request validation for prior call IDs.
        # Keep replay text-only; current turn tool usage is handled by AshAi.ToolLoop.
        Context.assistant(content || "")

      %{role: :user, content: content} ->
        Context.user(content || "")
    end)
  end

  defp append_event(items, value) when is_list(items), do: items ++ [value]
  defp append_event(_items, value), do: [value]

  defp normalize_tool_result(tool_call_id, {:ok, content, _raw}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: false
    }
  end

  defp normalize_tool_result(tool_call_id, {:error, content}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: true
    }
  end

  defp stream_error_text(nil), do: nil

  defp stream_error_text(:max_iterations_reached) do
    "I hit a response limit while generating this reply. Please try again."
  end

  defp stream_error_text(_reason) do
    "I hit an error while generating this response. Please try again."
  end
end
