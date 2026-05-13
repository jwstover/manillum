defmodule Manillum.Secrets do
  @moduledoc """
  Provides AshAuthentication with runtime secrets (e.g. token signing key).
  """

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
