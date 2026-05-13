defmodule Manillum.Accounts do
  @moduledoc """
  Ash domain for user accounts and authentication tokens.
  """

  use Ash.Domain, otp_app: :manillum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Manillum.Accounts.Token
    resource Manillum.Accounts.User
  end
end
