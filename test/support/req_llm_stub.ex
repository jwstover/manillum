defmodule Manillum.AI.ReqLLMStub do
  @moduledoc """
  Test double for `ReqLLM` used by `Manillum.AI.ReqLLM` (which delegates to
  this stub when `:manillum, :req_llm_module` is configured to point here).

  Two stubbed surfaces, one for prompt-backed actions and one for embeddings:

    * `put_response/1` + `generate_object/4` — for prompt actions. The
      response is the parsed object that AshAi expects from the LLM. For
      return-typed actions AshAi wraps the schema in `%{"result" => ...}`,
      so the stub returns `%{object: %{"result" => value}}` automatically.

    * `put_embedding/1` + `embed/3` — for the OpenAI embedding model. The
      registered value can be:
        - a single embedding vector (`[0.0, 0.1, ...]`) — repeated for every
          input passed to `embed/3`
        - a list of embedding vectors (`[[...], [...]]`) — must match the
          input list length
        - an `{:error, reason}` tuple — returned verbatim from `embed/3`

  This is the testing seam other streams (cataloging, future prompt actions)
  reuse.

  ## Examples

      setup do
        Manillum.AI.ReqLLMStub.put_response("hello back")
        Manillum.AI.ReqLLMStub.put_embedding(List.duplicate(0.0, 1536))
        on_exit(&Manillum.AI.ReqLLMStub.reset/0)
        :ok
      end

  """

  use Agent

  @doc false
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @doc "Register the next response from `generate_object/4`."
  @spec put_response(term()) :: :ok
  def put_response(value) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, :response, value))
  end

  @doc "Register the next response from `embed/3`."
  @spec put_embedding(term()) :: :ok
  def put_embedding(value) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, :embedding, value))
  end

  @doc "Clear all registered responses. Subsequent calls will raise."
  @spec reset() :: :ok
  def reset do
    ensure_started()
    Agent.update(__MODULE__, fn _ -> initial_state() end)
  end

  @doc """
  Stub of `ReqLLM.generate_object/4`. Returns
  `{:ok, %{object: %{"result" => value}}}` using the value most recently
  registered via `put_response/1`.
  """
  def generate_object(_model, _ctx, _schema, _opts) do
    ensure_started()

    case Agent.get(__MODULE__, & &1.response) do
      :unset ->
        raise "Manillum.AI.ReqLLMStub: no response registered. Call put_response/1 first."

      value ->
        {:ok, %{object: %{"result" => value}}}
    end
  end

  @doc """
  Stub of `ReqLLM.embed/3`. Returns the embedding(s) most recently registered
  via `put_embedding/1`. See moduledoc for accepted shapes.
  """
  def embed(_model, inputs, _opts) when is_list(inputs) do
    ensure_started()

    case Agent.get(__MODULE__, & &1.embedding) do
      :unset ->
        raise "Manillum.AI.ReqLLMStub: no embedding registered. Call put_embedding/1 first."

      {:error, _} = err ->
        err

      [first | _] = vector when is_number(first) ->
        {:ok, List.duplicate(vector, length(inputs))}

      embeddings when is_list(embeddings) ->
        {:ok, embeddings}
    end
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil -> start_link()
      _pid -> :ok
    end
  end

  defp initial_state, do: %{response: :unset, embedding: :unset}
end
