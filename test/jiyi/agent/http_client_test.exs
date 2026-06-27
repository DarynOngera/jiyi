defmodule Jiyi.Agent.HTTPClientTest do
  use Jiyi.DataCase

  alias Jiyi.Agent.{Config, HTTPClient}

  setup do
    unless Process.whereis(Jiyi.API.Supervisor) do
      start_supervised!(Jiyi.API.Supervisor)
    end

    vector = List.duplicate(0.0, 768)
    :meck.expect(Jiyi.EmbeddingClient.CircuitBreaker, :embed, fn _ -> {:ok, vector} end)

    on_exit(fn ->
      try do
        :meck.unload(Jiyi.EmbeddingClient.CircuitBreaker)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  test "writes and assembles memory over HTTP" do
    config =
      Config.new(
        agent_id: "http-agent",
        session_id: "http-session",
        api_key: "test-token",
        endpoint: http_endpoint(),
        transport: :http
      )

    {:ok, state} = HTTPClient.init(config)

    assert {:ok, %{"status" => "written", "id" => _}} =
             HTTPClient.memory_write(state, %{
               "type" => "semantic",
               "content" => %{
                 "subject" => "project",
                 "predicate" => "uses",
                 "object" => "Elixir"
               },
               "provenance" => %{
                 "source" => "agent_inference",
                 "ingestion_method" => "direct_write",
                 "trust_tier" => "agent_derived"
               },
               "scope" => "session_shared"
             })

    assert {:ok, %{"assembled_context" => context}} =
             HTTPClient.context_assemble(state, %{
               "task" => "What does the project use?",
               "memory_scopes" => ["session_shared"]
             })

    assert context =~ "Elixir"
  end

  test "uses per-agent key issued by /admin/agents" do
    agent_id = "http-agent-keyed"

    {:ok, %{status: 201, body: body}} =
      Finch.build(
        :post,
        "#{http_endpoint()}/admin/agents",
        [{"content-type", "application/json"}, {"authorization", "Bearer test-token"}],
        Jason.encode!(%{agent_id: agent_id})
      )
      |> Finch.request(Jiyi.Finch)

    %{"api_key" => api_key} = Jason.decode!(body)

    config =
      Config.new(
        agent_id: agent_id,
        session_id: "http-session",
        api_key: api_key,
        endpoint: http_endpoint(),
        transport: :http
      )

    {:ok, state} = HTTPClient.init(config)

    assert {:ok, %{"status" => "written"}} =
             HTTPClient.memory_write(state, %{
               "type" => "episodic",
               "content" => %{"summary" => "Per-agent key write test"},
               "provenance" => %{
                 "source" => "agent_observation",
                 "ingestion_method" => "direct_write",
                 "trust_tier" => "agent_derived"
               },
               "scope" => "agent_private"
             })
  end

  defp http_endpoint do
    port = Application.fetch_env!(:jiyi, :http_port)
    "http://localhost:#{port}"
  end
end
