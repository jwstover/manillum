import Config
config :manillum, Oban, testing: :manual
config :manillum, token_signing_secret: "l8wyuoWhLJtwy2iG0cP6NcNYK8tvJRph"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Route prompt-backed Ash actions through the in-process stub so tests never
# hit Anthropic/OpenAI. See `Manillum.AI.ReqLLMStub`.
config :manillum, req_llm_module: Manillum.AI.ReqLLMStub

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :manillum, Manillum.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5440,
  database: "manillum_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: Manillum.PostgrexTypes

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :manillum, ManillumWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4042],
  secret_key_base: "vsizOQLJCUvxKPKoNFTQcMKD0XcMMmxCN9FbDOWkjdov0P50ZpnAOC5dlU6TM6IL",
  server: false

# In test we don't send emails
config :manillum, Manillum.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
