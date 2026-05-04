defmodule Manillum.AI.Embedding.OpenAI do
  @moduledoc """
  `AshAi.EmbeddingModel` implementation backed by OpenAI's
  `text-embedding-3-small` model (1536 dimensions).

  Used by `vectorize` blocks on Ash resources to generate embeddings for
  semantic-similarity duplicate detection on cards.

  Calls flow through `Manillum.AI.ReqLLM` (which delegates to `ReqLLM` in
  prod and `Manillum.AI.ReqLLMStub` in tests). `ReqLLM` loads
  `OPENAI_API_KEY` from the environment (or `.env`) at startup.

  ## Examples

      iex> {:ok, [vector]} = Manillum.AI.Embedding.OpenAI.generate(["test"], [])
      iex> length(vector)
      1536

  """

  use AshAi.EmbeddingModel

  @model "openai:text-embedding-3-small"
  @dimensions 1536

  @impl true
  @spec dimensions(keyword()) :: pos_integer()
  def dimensions(_opts), do: @dimensions

  @impl true
  @spec generate([String.t()], keyword()) ::
          {:ok, [[float()]]} | {:error, term()}
  def generate(texts, opts) when is_list(texts) do
    inputs = Enum.map(texts, &(&1 || ""))

    case Manillum.AI.ReqLLM.embed(@model, inputs, opts) do
      {:ok, embeddings} when is_list(embeddings) -> {:ok, embeddings}
      {:error, error} -> {:error, error}
    end
  end
end
