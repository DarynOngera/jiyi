defmodule Jiyi.API.SupervisorTest do
  use ExUnit.Case

  alias Jiyi.API.Supervisor

  defmodule FakeMCPServer do
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        type: :worker
      }
    end

    def start_link(_opts) do
      Agent.start_link(fn -> :ok end, name: __MODULE__)
    end
  end

  test "uses configured :mcp_server_module in children" do
    original = Application.get_env(:jiyi, :mcp_server_module)
    Application.put_env(:jiyi, :mcp_server_module, FakeMCPServer)

    on_exit(fn ->
      if original do
        Application.put_env(:jiyi, :mcp_server_module, original)
      else
        Application.delete_env(:jiyi, :mcp_server_module)
      end
    end)

    assert {:ok, {_flags, child_specs}} = Supervisor.init([])

    assert %{id: FakeMCPServer, start: {FakeMCPServer, :start_link, [[transport: _]]}} =
             List.last(child_specs)
  end

  test "defaults to Jiyi.API.MCPServer when :mcp_server_module is not set" do
    original = Application.get_env(:jiyi, :mcp_server_module)
    Application.delete_env(:jiyi, :mcp_server_module)

    on_exit(fn ->
      if original do
        Application.put_env(:jiyi, :mcp_server_module, original)
      end
    end)

    assert Jiyi.API.MCPServer ==
             Application.get_env(:jiyi, :mcp_server_module, Jiyi.API.MCPServer)
  end
end
