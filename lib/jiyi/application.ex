defmodule Jiyi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Jiyi.Registry},
      Jiyi.Telemetry.Supervisor,
      Jiyi.Persistence.Supervisor,
      Jiyi.Memory.Supervisor,
      Jiyi.Retrieval.Supervisor,
      Jiyi.API.Supervisor,
      Jiyi.Anomaly.Supervisor
    ]

    children =
      if Application.fetch_env!(:jiyi, :embedding_server_enabled) do
        children ++ [Jiyi.EmbeddingServer.Supervisor]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Jiyi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
