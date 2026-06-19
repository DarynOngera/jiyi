defmodule Jiyi.Agent.HarnessTest do
  use Jiyi.DataCase

  alias Jiyi.Agent.{Config, Harness}

  defmodule FakeLLM do
    @behaviour Jiyi.Agent.LLM

    @impl true
    def chat(messages, _tools, _config) do
      if Enum.any?(messages, tool_result_message?()) do
        {:ok, %{content: "done", tool_calls: []}}
      else
        {:ok,
         %{
           content: nil,
           tool_calls: [
             %{
               id: "tool-1",
               name: "memory_write",
               arguments: %{
                 "type" => "semantic",
                 "content" => %{
                   "subject" => "project",
                   "predicate" => "uses",
                   "object" => "harness"
                 },
                 "provenance" => %{
                   "source" => "test",
                   "ingestion_method" => "direct_write",
                   "trust_tier" => "agent_derived"
                 },
                 "scope" => "session_shared"
               }
             }
           ]
         }}
      end
    end

    defp tool_result_message? do
      fn
        %{role: "user", content: "Tool result" <> _} -> true
        _ -> false
      end
    end
  end

  setup do
    unless Process.whereis(Jiyi.API.Supervisor) do
      start_supervised!(Jiyi.API.Supervisor)
    end

    :ok
  end

  test "runs agent loop and writes memory" do
    config =
      Config.new(
        agent_id: "harness-agent",
        session_id: "harness-session",
        api_key: "test-token",
        endpoint: "http://localhost:4001",
        transport: :http,
        llm: %{module: FakeLLM}
      )

    {:ok, pid} = Harness.start_link(config)

    assert {:ok, "done"} = Harness.run(pid, "remember the harness")

    {:ok, %{"assembled_context" => context}} =
      Jiyi.Agent.HTTPClient.context_assemble(
        config,
        %{
          "task" => "What does the project use?",
          "memory_scopes" => ["session_shared"]
        }
      )

    assert context =~ "harness"
  end
end
