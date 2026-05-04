defmodule Manillum.AI.ReqLLM do
  @moduledoc """
  Indirection layer between AshAI prompt actions and the underlying ReqLLM
  client. Lets test code swap in `Manillum.AI.ReqLLMStub` without touching the
  action declarations — set `:manillum, :req_llm_module` to override.

  Only the surface area used by `AshAi.Actions.Prompt` (and its tool loop)
  is delegated. Add to it as new prompt-action features come online.
  """

  @doc false
  def generate_object(model, context, schema, opts) do
    impl().generate_object(model, context, schema, opts)
  end

  defp impl do
    Application.get_env(:manillum, :req_llm_module, ReqLLM)
  end
end
