defmodule Manillum.Conversations.Message.Types.Role do
  use Ash.Type.Enum, values: [:user, :assistant]
end
