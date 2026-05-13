defmodule Manillum.Conversations.Conversation.Changes.GenerateName do
  @moduledoc """
  Generates a human-readable name for a conversation by asking the LLM to
  summarize its early messages.
  """

  use Ash.Resource.Change
  require Ash.Query

  alias Manillum.Conversations.Conversation.NamePrompt

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      conversation = changeset.data

      messages =
        Manillum.Conversations.Message
        |> Ash.Query.filter(conversation_id == ^conversation.id)
        |> Ash.Query.limit(10)
        |> Ash.Query.select([:content, :role])
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(scope: context)

      prompt = NamePrompt.build(messages)

      with {:ok, response} <-
             ReqLLM.generate_text("anthropic:claude-sonnet-4-5", prompt,
               max_tokens: NamePrompt.max_tokens()
             ),
           raw <- ReqLLM.Response.text(response),
           {:ok, title} <- NamePrompt.parse_response(raw) do
        Ash.Changeset.force_change_attribute(changeset, :title, title)
      else
        {:error, reason} ->
          {:error, reason}
      end
    end)
  end
end
