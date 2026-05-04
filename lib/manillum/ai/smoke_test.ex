defmodule Manillum.AI.SmokeTest do
  @moduledoc """
  Trivial prompt-backed Ash action used to verify the Anthropic + AshAI wiring
  end-to-end. Calling `Manillum.AI.SmokeTest.echo("hi")` from IEx hits Claude
  Haiku 4.5 and returns the model's reply as a string. Not used by the product;
  exists only as a smoke test (Stream A Gate A.2) and as a worked example of
  the prompt-action pattern other streams will follow.
  """

  use Ash.Resource,
    domain: Manillum.AI,
    extensions: [AshAi]

  code_interface do
    domain Manillum.AI
    define :echo, args: [:text]
  end

  actions do
    action :echo, :string do
      description """
      Echo the input text back via Claude Haiku 4.5. Used purely to verify that
      Anthropic API access is wired up and prompt-backed actions work.
      """

      argument :text, :string do
        allow_nil? false
        description "Text to echo back"
      end

      run prompt("anthropic:claude-haiku-4-5",
            req_llm: Manillum.AI.ReqLLM,
            tools: false,
            prompt:
              {"You are a smoke-test echo. Reply with a short acknowledgement that confirms you received the user's text. Do not add commentary.",
               "Acknowledge this text: <%= @input.arguments.text %>"}
          )
    end
  end
end
