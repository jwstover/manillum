defmodule Manillum.Conversations do
  @moduledoc """
  Ash domain for chat conversations, messages, and timeline mentions.

  Exposes AshAi tools the LLM can call (e.g. listing conversations, reading
  message history, placing timeline mentions).
  """

  use Ash.Domain, otp_app: :manillum, extensions: [AshAi, AshPhoenix]

  tools do
    tool :chat_list_conversations, Manillum.Conversations.Conversation, :my_conversations do
      description "List chat conversations visible to the current actor."
    end

    tool :chat_message_history, Manillum.Conversations.Message, :for_conversation do
      description "Read chat messages for a conversation_id."
    end

    tool :place_event_on_timeline, Manillum.Conversations.Mention, :place_event_on_timeline do
      description """
      Place a marker on the user's history timeline for a specific dated event.

      Use when the conversation establishes a concrete historical event tied
      to a known year — e.g. battles, treaties, deaths, foundings, eruptions.
      Skip allusions, periods (\"the Renaissance\"), and timeless concepts.

      Provide as much date precision as you're confident in. Leave `month`
      and `day` nil rather than guessing — a year-only mention is fine.
      `day` requires `month`. BC years use negative integers (44 BC = -44,
      Battle of Hastings = 1066).

      Safe to call multiple times in one turn for multiple events. Repeats
      of the same `(year, title)` in the same conversation are idempotent —
      the tool returns the existing mention.
      """
    end
  end

  resources do
    resource Manillum.Conversations.Conversation do
      define :create_conversation, action: :create
      define :get_conversation, action: :read, get_by: [:id]
      define :my_conversations
    end

    resource Manillum.Conversations.Message do
      define :message_history,
        action: :for_conversation,
        args: [:conversation_id],
        default_options: [query: [sort: [inserted_at: :desc]]]

      define :create_message, action: :create
    end

    resource Manillum.Conversations.Mention do
      define :list_mentions, action: :for_conversation, args: [:conversation_id]
    end
  end
end
