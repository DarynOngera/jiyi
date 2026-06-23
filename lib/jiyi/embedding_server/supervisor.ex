defmodule Jiyi.EmbeddingServer.Supervisor do
  @moduledoc """
  Supervises the local embedding model serving and its HTTP endpoint.

  Started only when :jiyi :embedding_server_enabled is true.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    port = Application.fetch_env!(:jiyi, :embedding_server_port)

    children = [
      Jiyi.EmbeddingServer,
      {Bandit, plug: Jiyi.EmbeddingServer.HTTP, scheme: :http, port: port}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
