defmodule Manillum.Conversations.Message.Types.Role do
  @moduledoc """
  Enum type for the speaker of a conversation message (`:user` or `:assistant`).
  """

  use Ash.Type.Enum, values: [:user, :assistant]
end
