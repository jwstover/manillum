defmodule Manillum.AI do
  @moduledoc """
  Namespace for AI-related modules that don't belong to a feature domain.

  Hosts:

    * `Manillum.AI.Embedding.OpenAI` — `AshAi.EmbeddingModel` impl backed by
      OpenAI's `text-embedding-3-small` model.
    * `Manillum.AI.ReqLLM` — indirection layer between AshAI prompt actions
      and the underlying `ReqLLM` client. Tests swap in
      `Manillum.AI.ReqLLMStub` (in `test/support/`) via the
      `:manillum, :req_llm_module` config key.

  **Manillum.AI is intentionally not an Ash domain and hosts no Ash resources.**
  Prompt-backed actions live on whatever feature domain owns their output:

    * Cataloging on `Manillum.Archive` (via the `Capture` resource — see the
      MVP spec §5 Stream C).
    * Chat on `Manillum.Conversations` (Stream D, scaffolded by
      `mix ash_ai.gen.chat`).
    * Future review-prompt generation on `Manillum.Reviews`.

  No other module calls Anthropic or OpenAI directly — the boundary is
  enforced by convention and code review, not by domain membership.
  """
end
