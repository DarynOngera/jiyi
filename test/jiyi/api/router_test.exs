defmodule Jiyi.API.RouterTest do
  use ExUnit.Case

  alias Jiyi.API.Router

  setup do
    if Process.whereis(Jiyi.Repo) do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Jiyi.Repo)
      Ecto.Adapters.SQL.Sandbox.mode(Jiyi.Repo, {:shared, self()})
    end

    unless Process.whereis(Jiyi.Retrieval.Supervisor) do
      start_supervised!(Jiyi.Retrieval.Supervisor)
    end

    :ok
  end

  describe "router" do
    test "returns 401 without bearer token" do
      conn =
        :post
        |> Plug.Test.conn("/context/assemble", %{agent_id: "a", session_id: "s", task: "t"})
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Router.call([])

      assert conn.status == 401
    end

    test "returns 200 with valid bearer token" do
      conn =
        :post
        |> Plug.Test.conn("/context/assemble", %{agent_id: "a", session_id: "s", task: "t"})
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer test-token")
        |> Router.call([])

      assert conn.status == 200

      assert %{
               "assembled_context" => _,
               "sources" => _,
               "token_count" => _
             } = Jason.decode!(conn.resp_body)
    end
  end
end
