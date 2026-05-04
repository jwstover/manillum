defmodule Manillum.AI.ReqLLM do
  @moduledoc """
  Indirection layer between AshAI / `Manillum.AI` and the underlying ReqLLM
  client. Lets test code swap in `Manillum.AI.ReqLLMStub` without touching the
  call sites — set `:manillum, :req_llm_module` to override.

  Only the surface area used by `Manillum.AI` is delegated. Add to it as new
  prompt-action features come online.
  """

  @doc false
  @spec generate_object(String.t(), term(), term(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def generate_object(model, context, schema, opts) do
    impl().generate_object(model, context, schema, opts)
  end

  @doc false
  @spec embed(String.t(), [String.t()], keyword()) ::
          {:ok, [[float()]]} | {:error, term()}
  def embed(model, inputs, opts) do
    impl().embed(model, inputs, opts)
  end

  defp impl do
    Application.get_env(:manillum, :req_llm_module, ReqLLM)
  end
end
