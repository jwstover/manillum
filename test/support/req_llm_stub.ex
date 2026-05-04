defmodule Manillum.AI.ReqLLMStub do
  @moduledoc """
  Test double for `ReqLLM` used by prompt-backed Ash actions.

  Prompt-backed Ash actions in `Manillum.AI` call through `Manillum.AI.ReqLLM`,
  which delegates to whatever module is configured under
  `:manillum, :req_llm_module`. `config/test.exs` points that at this stub, so
  no real HTTP traffic ever happens in tests.

  Tests register canned responses via `put_response/1`. The response is the
  parsed object that AshAi expects from the LLM — for return-typed actions
  AshAi wraps the schema in `%{"result" => ...}`, so the stub returns
  `%{"result" => value}` automatically.

  This is the testing seam that other streams (e.g. cataloging) reuse for
  their own prompt-action tests.

  ## Example

      setup do
        Manillum.AI.ReqLLMStub.put_response("hello back")
        :ok
      end

      test "echo returns the LLM response" do
        assert {:ok, "hello back"} = Manillum.AI.SmokeTest.echo("hi")
      end
  """

  use Agent

  @doc false
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{response: :unset} end, name: __MODULE__)
  end

  @doc "Register the next response from `generate_object/4`."
  @spec put_response(term()) :: :ok
  def put_response(value) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, :response, value))
  end

  @doc "Clear the registered response. Subsequent calls will raise."
  @spec reset() :: :ok
  def reset do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, :response, :unset))
  end

  @doc """
  Stub of `ReqLLM.generate_object/4`. Returns `{:ok, %{object: %{"result" => value}}}`
  using the value most recently registered via `put_response/1`.
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

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil -> start_link()
      _pid -> :ok
    end
  end
end
