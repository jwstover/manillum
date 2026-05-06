defmodule Manillum.AI.Embedding.OpenAITest do
  # async: false because `Manillum.AI.ReqLLMStub` is a process-global Agent.
  use ExUnit.Case, async: false

  alias Manillum.AI.Embedding.OpenAI
  alias Manillum.AI.ReqLLMStub

  describe "behaviour contract" do
    test "implements AshAi.EmbeddingModel" do
      behaviours =
        OpenAI.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      assert AshAi.EmbeddingModel in behaviours
    end

    test "dimensions/1 returns 1536 regardless of opts" do
      assert OpenAI.dimensions([]) == 1536
      assert OpenAI.dimensions(some: :opt) == 1536
    end
  end

  describe "generate/2" do
    setup do
      # Reset before each test rather than on_exit — `ReqLLMStub` is an
      # Agent linked to the calling test process and dies with it, so
      # on_exit handlers can race against name unregistration.
      ReqLLMStub.reset()
      :ok
    end

    test "returns one stubbed embedding per input" do
      vector = List.duplicate(0.5, 1536)
      ReqLLMStub.put_embedding(vector)

      assert {:ok, [v1, v2]} = OpenAI.generate(["alpha", "beta"], [])
      assert length(v1) == 1536
      assert length(v2) == 1536
    end

    test "passes per-input embeddings through unchanged when shapes match" do
      v1 = List.duplicate(0.1, 1536)
      v2 = List.duplicate(0.2, 1536)
      ReqLLMStub.put_embedding([v1, v2])

      assert {:ok, [^v1, ^v2]} = OpenAI.generate(["a", "b"], [])
    end

    test "maps nil inputs to empty strings rather than crashing" do
      ReqLLMStub.put_embedding(List.duplicate(0.0, 1536))

      assert {:ok, [vector]} = OpenAI.generate([nil], [])
      assert length(vector) == 1536
    end

    test "bubbles up errors from the underlying client" do
      ReqLLMStub.put_embedding({:error, :rate_limited})

      assert {:error, :rate_limited} = OpenAI.generate(["alpha"], [])
    end
  end
end
