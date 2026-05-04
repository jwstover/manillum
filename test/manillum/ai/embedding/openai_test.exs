defmodule Manillum.AI.Embedding.OpenAITest do
  use ExUnit.Case, async: true

  alias Manillum.AI.Embedding.OpenAI

  describe "behavior contract" do
    test "implements AshAi.EmbeddingModel" do
      behaviours =
        OpenAI.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      assert AshAi.EmbeddingModel in behaviours
    end

    test "dimensions/1 returns 1536 regardless of opts" do
      assert OpenAI.dimensions([]) == 1536
      assert OpenAI.dimensions(some: :opt) == 1536
    end

    test "generate/2 is exported with arity 2" do
      assert function_exported?(OpenAI, :generate, 2)
    end
  end
end
