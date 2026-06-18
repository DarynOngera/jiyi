defmodule Jiyi.API.RouterTest do
  use Jiyi.DataCase

  alias Jiyi.API.Router
  alias Jiyi.Schemas.AgentKey

  setup do
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

    test "returns 200 with shared bearer token" do
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

    test "returns 200 with per-agent key matching agent_id" do
      agent_id = "agent-#{System.unique_integer([:positive])}"
      token = "agent-key-#{System.unique_integer([:positive])}"
      insert_agent_key(token, agent_id)

      conn =
        :post
        |> Plug.Test.conn("/context/assemble", %{
          agent_id: agent_id,
          session_id: "s",
          task: "t"
        })
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Router.call([])

      assert conn.status == 200
    end

    test "returns 403 when per-agent key agent_id does not match" do
      token = "agent-key-#{System.unique_integer([:positive])}"
      insert_agent_key(token, "agent-a")

      conn =
        :post
        |> Plug.Test.conn("/context/assemble", %{
          agent_id: "agent-b",
          session_id: "s",
          task: "t"
        })
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Router.call([])

      assert conn.status == 403
      assert %{"error" => "agent_id_mismatch"} = Jason.decode!(conn.resp_body)
    end

    test "returns 401 for invalid token" do
      conn =
        :post
        |> Plug.Test.conn("/context/assemble", %{agent_id: "a", session_id: "s", task: "t"})
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer invalid-token")
        |> Router.call([])

      assert conn.status == 401
    end

    test "issues mcp session token with shared bearer token" do
      agent_id = "agent-#{System.unique_integer([:positive])}"

      conn =
        :post
        |> Plug.Test.conn("/auth/mcp-token", %{agent_id: agent_id})
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer test-token")
        |> Router.call([])

      assert conn.status == 200

      assert %{
               "token" => token,
               "expires_in" => 300
             } = Jason.decode!(conn.resp_body)

      assert is_binary(token)
    end

    test "issues mcp session token with per-agent key" do
      agent_id = "agent-#{System.unique_integer([:positive])}"
      token = "agent-key-#{System.unique_integer([:positive])}"
      insert_agent_key(token, agent_id)

      conn =
        :post
        |> Plug.Test.conn("/auth/mcp-token", %{agent_id: agent_id})
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> Router.call([])

      assert conn.status == 200

      assert %{
               "token" => _,
               "expires_in" => 300
             } = Jason.decode!(conn.resp_body)
    end
  end

  defp insert_agent_key(token, agent_id) do
    hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    %AgentKey{}
    |> AgentKey.changeset(%{
      key_hash: hash,
      agent_id: agent_id,
      inserted_at: DateTime.utc_now()
    })
    |> Jiyi.Repo.insert!()
  end
end
