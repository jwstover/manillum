defmodule Manillum.Conversations.Conversation.NamePrompt do
  @moduledoc """
  Builds the prompt used by `Manillum.Conversations.Conversation.Changes.GenerateName`
  to produce a short title for a chat conversation, and parses the model's
  response back into a clean title string.

  Pulled out of the change module so the prompt can be iterated against a
  fixture set in `notebooks/conversation_naming.livemd` without invoking the
  Oban trigger or the DB. Production code calls `system_message/0`,
  `user_message/1`, and `parse_response/1` here; the notebook calls the
  same functions.

  ## Why these prompt choices

  Anthropic's prompt-engineering guidance for short, format-constrained
  outputs on long contexts says: put the variable content (the conversation)
  near the top of the prompt and the instruction at the end (queries at the
  end can improve response quality by up to 30% on long-context inputs);
  wrap the variable content and the desired output shape in XML tags so the
  model can distinguish "stuff to read" from "what to produce"; show 3–5
  diverse few-shot examples; tell the model what to do rather than what
  not to do; cap output length physically with `max_tokens` rather than
  relying on instruction following alone.

  The previous one-line system prompt ("Provide a short name for the current
  conversation. 2-8 words... RESPOND WITH ONLY THE NEW CONVERSATION NAME.")
  followed by the raw conversation history triggered classic instruction
  drift: by the time the model produced its answer, its most-recent context
  was the assistant's own bullet-pointed history reply, and it continued in
  that style rather than obeying the original instruction. The new layout
  fixes this by (a) wrapping the conversation in `<conversation>` tags so
  it's visibly "input, not the next turn to continue", (b) putting the
  instruction *after* the conversation, (c) requiring the answer wrapped in
  `<title>…</title>` so a malformed response is detectable, and (d)
  pairing with `max_tokens: 40` at the call site so even a misbehaving
  response can't produce 301 characters.
  """

  @max_title_chars 80

  @doc """
  Recommended `max_tokens` cap for the underlying ReqLLM call. 3–8 words
  plus the `<title>…</title>` tags is well under 40 tokens; the buffer is
  there so a long title isn't truncated mid-word but the call still can't
  produce a 300-char markdown blob the way the old prompt could.
  """
  def max_tokens, do: 40

  @doc """
  Maximum allowed character length for an extracted title. Used by
  `parse_response/1` to drop suspiciously long results.
  """
  def max_title_chars, do: @max_title_chars

  @doc """
  System message — assigns the model's role and nothing else. Format
  constraints + examples live in the user message so they sit right next
  to the conversation they apply to.
  """
  def system_message do
    """
    You are a librarian who writes short titles for chat conversations.
    Each conversation is between a user and Livy, a history-learning assistant.
    Your job is to read the transcript and produce a title naming what the
    conversation is about.
    """
  end

  @doc """
  User message — three few-shot examples, then the conversation to title,
  then the format instruction. Examples are deliberately diverse: a single-
  exchange question, a short follow-up exchange that pivots, and a
  multi-turn conversation that drifts across topics.

  `messages` is a list of `%{role: :user | :assistant, content: binary()}`.
  Either the persisted resource or a plain map will work.
  """
  def user_message(messages) when is_list(messages) do
    """
    Below are example conversations and their titles, then a new conversation you should title.

    <examples>
      <example>
        <conversation>
          <user>Why did the Bronze Age collapse?</user>
          <assistant>Most historians treat it as a systems collapse — between roughly 1200 and 1150 BCE every major palace economy in the eastern Mediterranean fell within fifty years. Drought, severed trade, internal rebellion, and the Sea Peoples all contributed.</assistant>
        </conversation>
        <title>Bronze Age systems collapse</title>
      </example>
      <example>
        <conversation>
          <user>Tell me about the printing press.</user>
          <assistant>Gutenberg's movable-type press around 1440 dropped the cost of books by an order of magnitude over a generation, accelerating literacy, the Reformation, and the scientific revolution.</assistant>
          <user>Was it actually invented in Europe first?</user>
          <assistant>No — Bi Sheng built movable clay type in Song-dynasty China around 1040, four centuries earlier. Gutenberg's innovation was the metal alloy and the press itself, suited to alphabetic scripts.</assistant>
        </conversation>
        <title>Origins of the printing press</title>
      </example>
      <example>
        <conversation>
          <user>What was the spice trade?</user>
          <assistant>The long-distance trade in pepper, cloves, nutmeg, and cinnamon between the Indian Ocean and Europe, dominated by Venice and Arab middlemen until the late 15th century.</assistant>
          <user>How did Portugal break the Venetian monopoly?</user>
          <assistant>Vasco da Gama's 1498 voyage round the Cape of Good Hope opened a sea route to India that bypassed the Mediterranean intermediaries, collapsing Venetian margins within a generation.</assistant>
        </conversation>
        <title>Spice trade and Portuguese expansion</title>
      </example>
    </examples>

    <conversation>
    #{format_messages(messages)}
    </conversation>

    Title the conversation above. Format requirements:
    - 3 to 8 words.
    - Plain text on a single line — no markdown, no quotation marks, no trailing punctuation.
    - Sentence case: capitalize the first word and proper nouns. Do not Title-Case every word.
    - Describe the subject of the conversation, not the user's intent. Prefer noun phrases like "Bronze Age systems collapse" over "Discussion of the Bronze Age".

    Output the title inside <title>…</title> tags. Output nothing else.
    """
  end

  @doc """
  Build the full prompt as a list of `ReqLLM.Context` messages, ready to
  pass to `ReqLLM.generate_text/2`.
  """
  def build(messages) do
    alias ReqLLM.Context

    [
      Context.system(system_message()),
      Context.user(user_message(messages))
    ]
  end

  @doc """
  Parse the model's response into a clean title string, or `{:error, reason}`
  if the response can't be coerced into a sensible title.

  Strategy:
  - Pull content out of the first `<title>…</title>` tag pair.
  - Fall back to the raw response if no tags are present (older / less-
    compliant models still produce usable bare titles most of the time).
  - Strip leading/trailing whitespace and a couple of common over-formatting
    artifacts (surrounding quotes, trailing periods, leading "Title: ").
  - Reject anything still longer than `max_title_chars/0` after cleanup.
  """
  def parse_response(text) when is_binary(text) do
    text
    |> extract_title_tag()
    |> clean()
    |> validate()
  end

  def parse_response(_), do: {:error, :invalid_response}

  defp extract_title_tag(text) do
    case Regex.run(~r/<title>(.*?)<\/title>/si, text, capture: :all_but_first) do
      [inner] -> inner
      _ -> text
    end
  end

  defp clean(text) do
    text
    |> String.trim()
    # Drop a leading "Title:" or "Conversation title:" if the model added one.
    # Run BEFORE quote stripping so a `Title: "Foo"` payload has its quotes
    # at the boundary by the time the quote-strip pass sees it.
    |> String.replace(~r/^\s*(?:conversation\s+)?title\s*:\s*/i, "")
    # Strip a single layer of surrounding straight or smart quotes.
    |> String.replace(~r/^["'“”‘’]+|["'“”‘’]+$/u, "")
    # Collapse internal whitespace runs (incl. newlines) to a single space —
    # multi-line titles get flattened rather than rejected outright.
    |> String.replace(~r/\s+/u, " ")
    # Strip a trailing period or full-stop the model sometimes appends.
    |> String.replace(~r/[.\s]+$/u, "")
    |> String.trim()
  end

  defp validate(""), do: {:error, :empty_title}

  defp validate(title) do
    cond do
      String.length(title) > @max_title_chars ->
        {:error, {:title_too_long, String.length(title)}}

      String.contains?(title, ["**", "###", "##", "\n"]) ->
        {:error, :title_contains_markdown}

      true ->
        {:ok, title}
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp format_messages(messages) do
    Enum.map_join(messages, "\n", &format_message/1)
  end

  defp format_message(%{role: role, content: content}) when role in [:user, "user"],
    do: "  <user>#{escape(content)}</user>"

  defp format_message(%{role: role, content: content})
       when role in [:assistant, "assistant"],
       do: "  <assistant>#{escape(content)}</assistant>"

  defp format_message(_), do: ""

  # Minimal XML-ish escape — the conversation content can include `<` and
  # `>` (e.g. discussing a `<head>` HTML tag). Escaping just `<` and `>`
  # keeps the prompt structurally parseable without trying to be a full
  # XML serializer.
  defp escape(nil), do: ""

  defp escape(content) when is_binary(content) do
    content
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
