defmodule Manillum.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Force-load custom Postgrex types module before Repo connections start so
    # the BEAM never tries to dispatch encode_params/2 against a not-yet-loaded
    # module (cause of intermittent Oban producer crashes in dev).
    Code.ensure_loaded!(Manillum.PostgrexTypes)

    children = [
      ManillumWeb.Telemetry,
      Manillum.Repo,
      {DNSCluster, query: Application.get_env(:manillum, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:manillum, :ash_domains),
         Application.fetch_env!(:manillum, Oban)
       )},
      {Phoenix.PubSub, name: Manillum.PubSub},
      # Start a worker by calling: Manillum.Worker.start_link(arg)
      # {Manillum.Worker, arg},
      # Start to serve requests, typically the last entry
      ManillumWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :manillum]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Manillum.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ManillumWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
