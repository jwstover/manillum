defmodule Manillum.Accounts do
  use Ash.Domain, otp_app: :manillum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Manillum.Accounts.Token
    resource Manillum.Accounts.User
  end
end
