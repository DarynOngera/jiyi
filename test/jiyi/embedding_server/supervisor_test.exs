defmodule Jiyi.EmbeddingServer.SupervisorTest do
  use ExUnit.Case

  test "init returns EmbeddingServer and Bandit children" do
    original = Application.get_env(:jiyi, :embedding_server_port)
    Application.put_env(:jiyi, :embedding_server_port, 9001)

    on_exit(fn ->
      Application.put_env(:jiyi, :embedding_server_port, original)
    end)

    assert {:ok, {_flags, child_specs}} = Jiyi.EmbeddingServer.Supervisor.init([])

    assert Enum.any?(child_specs, &(&1.id == Jiyi.EmbeddingServer))

    bandit_spec = Enum.find(child_specs, fn spec -> match?({Bandit, _}, spec.id) end)
    assert bandit_spec

    assert {
             Bandit,
             :start_link,
             [[plug: Jiyi.EmbeddingServer.HTTP, scheme: :http, port: 9001]]
           } = bandit_spec.start
  end
end
