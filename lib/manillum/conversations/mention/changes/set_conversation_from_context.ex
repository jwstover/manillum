defmodule Manillum.Conversations.Mention.Changes.SetConversationFromContext do
  @moduledoc """
  Pulls `conversation_id` and `message_id` from the action's context map and
  stamps them onto the changeset.

  Used by the `:place_event_on_timeline` tool action. The LLM cannot supply
  these directly (the tool schema only exposes the historical-fact fields);
  instead `Manillum.Conversations.Message.Changes.Respond` injects them into
  the tool-loop context map before invoking `AshAi.ToolLoop.stream`, and
  AshAi propagates the context through to the action invocation here.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    cid = Map.get(changeset.context, :current_conversation_id)
    mid = Map.get(changeset.context, :current_message_id)

    if is_binary(cid) and is_binary(mid) do
      changeset
      |> Ash.Changeset.change_attribute(:conversation_id, cid)
      |> Ash.Changeset.change_attribute(:message_id, mid)
    else
      Ash.Changeset.add_error(
        changeset,
        field: :conversation_id,
        message:
          "missing :current_conversation_id / :current_message_id in action context. " <>
            "This action is intended to be invoked from within the chat tool loop."
      )
    end
  end
end
