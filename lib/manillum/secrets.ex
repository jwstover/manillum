defmodule Manillum.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Manillum.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:manillum, :token_signing_secret)
  end
end
