defmodule Manillum.AI.SmokeTestTest do
  use ExUnit.Case, async: false

  alias Manillum.AI.SmokeTest, as: Smoke

  setup do
    Manillum.AI.ReqLLMStub.put_response("hello back")
    on_exit(&Manillum.AI.ReqLLMStub.reset/0)
    :ok
  end

  test "echo/1 returns the LLM response via the stub" do
    assert {:ok, "hello back"} = Smoke.echo("hi")
  end

  test "echo/1 requires a non-nil text argument" do
    assert {:error, _} = Smoke.echo(nil)
  end
end
