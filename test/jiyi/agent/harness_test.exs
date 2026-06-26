defmodule Jiyi.Agent.HarnessTest do
  use Jiyi.DataCase

  alias Jiyi.Agent.{Config, Harness}

  defmodule FakeLLM do
    @behaviour Jiyi.Agent.LLM

    @impl true
    def chat(messages, _tools, config) do
      if Map.get(config, :calls) do
        Agent.update(config.calls, &[{:llm_chat} | &1])
      end

      case Map.get(config, :behavior) do
        :echo ->
          {:ok, %{content: "ok", tool_calls: []}}

        :tool_unknown ->
          if has_tool_result?(messages) do
            {:ok, %{content: "done", tool_calls: []}}
          else
            {:ok,
             %{
               content: nil,
               tool_calls: [
                 %{id: "tool-1", name: "unknown_tool", arguments: %{}}
               ]
             }}
          end

        :memory_tool ->
          if has_tool_result?(messages) do
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

        :context_tool ->
          if has_tool_result?(messages) do
            {:ok, %{content: "done", tool_calls: []}}
          else
            {:ok,
             %{
               content: nil,
               tool_calls: [
                 %{
                   id: "tool-1",
                   name: "context_assemble",
                   arguments: %{"task" => "subtask"}
                 }
               ]
             }}
          end

        _ ->
          if has_tool_result?(messages) do
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
    end

    defp has_tool_result?(messages) do
      Enum.any?(messages, fn
        %{role: "user", content: "Tool result" <> _} -> true
        _ -> false
      end)
    end
  end

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

      try do
        :meck.unload(Jiyi.Agent.HTTPClient)
      rescue
        _ -> :ok
      end
    end)

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

  test "writes active_task to working memory before LLM call" do
    {:ok, calls} = Agent.start(fn -> [] end)

    :meck.new(Jiyi.Agent.HTTPClient, [:passthrough])

    :meck.expect(Jiyi.Agent.HTTPClient, :memory_write, fn _state, request ->
      Agent.update(calls, &[{:memory_write, request} | &1])
      {:ok, %{"status" => "written", "id" => "fake"}}
    end)

    :meck.expect(Jiyi.Agent.HTTPClient, :context_assemble, fn _state, request ->
      Agent.update(calls, &[{:context_assemble, request} | &1])
      {:ok, %{"assembled_context" => "", "sources" => []}}
    end)

    config =
      Config.new(
        agent_id: "harness-agent",
        session_id: "harness-session",
        api_key: "test-token",
        endpoint: "http://localhost:4001",
        transport: :http,
        llm: %{module: FakeLLM, behavior: :echo, calls: calls}
      )

    {:ok, pid} = Harness.start_link(config)

    assert {:ok, "ok"} = Harness.run(pid, "test task")

    recorded = Agent.get(calls, &Enum.reverse/1)

    assert {:memory_write, first} = Enum.at(recorded, 0)
    assert first["type"] == "working"
    assert first["content"]["active_task"] == "test task"

    assert {:context_assemble, _} = Enum.at(recorded, 2)
    assert {:llm_chat} = Enum.at(recorded, 3)
  end

  test "episodic hook fires after a non-memory tool call" do
    {:ok, calls} = Agent.start(fn -> [] end)

    :meck.new(Jiyi.Agent.HTTPClient, [:passthrough])

    :meck.expect(Jiyi.Agent.HTTPClient, :memory_write, fn _state, request ->
      Agent.update(calls, &[{:memory_write, request} | &1])

      if request["type"] == "episodic" do
        {:ok, %{"status" => "written", "id" => "episodic-1"}}
      else
        {:ok, %{"status" => "written", "id" => "other"}}
      end
    end)

    :meck.expect(Jiyi.Agent.HTTPClient, :context_assemble, fn _state, _request ->
      {:ok, %{"assembled_context" => "", "sources" => []}}
    end)

    config =
      Config.new(
        agent_id: "harness-agent",
        session_id: "harness-session",
        api_key: "test-token",
        endpoint: "http://localhost:4001",
        transport: :http,
        llm: %{module: FakeLLM, behavior: :tool_unknown}
      )

    {:ok, pid} = Harness.start_link(config)

    assert {:ok, "done"} = Harness.run(pid, "run the tool")

    recorded = Agent.get(calls, &Enum.reverse/1)

    episodic_writes =
      Enum.filter(recorded, fn
        {:memory_write, %{"type" => "episodic"}} -> true
        _ -> false
      end)

    assert length(episodic_writes) == 1

    {:memory_write, request} = hd(episodic_writes)
    assert request["content"]["summary"] =~ "Tool unknown_tool returned: error: :unknown_tool"
    assert request["provenance"]["ingestion_method"] == "tool_result"
    assert request["provenance"]["trust_tier"] == "agent_derived"
    assert request["scope"] == "agent_private"
  end

  test "episodic hook does not fire for memory_write or context_assemble" do
    {:ok, calls} = Agent.start(fn -> [] end)

    :meck.new(Jiyi.Agent.HTTPClient, [:passthrough])

    :meck.expect(Jiyi.Agent.HTTPClient, :memory_write, fn _state, request ->
      Agent.update(calls, &[{:memory_write, request} | &1])
      {:ok, %{"status" => "written", "id" => "fake"}}
    end)

    :meck.expect(Jiyi.Agent.HTTPClient, :context_assemble, fn _state, _request ->
      Agent.update(calls, &[{:context_assemble} | &1])
      {:ok, %{"assembled_context" => "", "sources" => []}}
    end)

    for behavior <- [:memory_tool, :context_tool] do
      config =
        Config.new(
          agent_id: "harness-agent",
          session_id: "harness-session",
          api_key: "test-token",
          endpoint: "http://localhost:4001",
          transport: :http,
          llm: %{module: FakeLLM, behavior: behavior}
        )

      {:ok, pid} = Harness.start_link(config)
      assert {:ok, "done"} = Harness.run(pid, "tool call")
    end

    recorded = Agent.get(calls, &Enum.reverse/1)

    episodic_writes =
      Enum.filter(recorded, fn
        {:memory_write, %{"type" => "episodic"}} -> true
        _ -> false
      end)

    assert episodic_writes == []
  end

  test "second context_assemble is called when task shifts between turns" do
    {:ok, calls} = Agent.start(fn -> [] end)

    :meck.new(Jiyi.Agent.HTTPClient, [:passthrough])

    :meck.expect(Jiyi.Agent.HTTPClient, :memory_write, fn _state, request ->
      Agent.update(calls, &[{:memory_write, request} | &1])
      {:ok, %{"status" => "written", "id" => "fake"}}
    end)

    :meck.expect(Jiyi.Agent.HTTPClient, :context_assemble, fn _state, request ->
      Agent.update(calls, &[{:context_assemble, request["task"]} | &1])
      {:ok, %{"assembled_context" => "context for #{request["task"]}", "sources" => []}}
    end)

    config =
      Config.new(
        agent_id: "harness-agent",
        session_id: "harness-session",
        api_key: "test-token",
        endpoint: "http://localhost:4001",
        transport: :http,
        llm: %{module: FakeLLM, behavior: :echo}
      )

    {:ok, pid} = Harness.start_link(config)

    assert {:ok, "ok"} = Harness.run(pid, "tell me about apples")
    assert {:ok, "ok"} = Harness.run(pid, "explain quantum physics")

    recorded = Agent.get(calls, &Enum.reverse/1)

    assemble_tasks =
      Enum.filter(recorded, fn
        {:context_assemble, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:context_assemble, task} -> task end)

    assert hd(assemble_tasks) == "tell me about apples"
    assert Enum.count(assemble_tasks, &(&1 == "explain quantum physics")) == 2
  end

  test "second context_assemble is not called when task is unchanged" do
    {:ok, calls} = Agent.start(fn -> [] end)

    :meck.new(Jiyi.Agent.HTTPClient, [:passthrough])

    :meck.expect(Jiyi.Agent.HTTPClient, :memory_write, fn _state, request ->
      Agent.update(calls, &[{:memory_write, request} | &1])
      {:ok, %{"status" => "written", "id" => "fake"}}
    end)

    :meck.expect(Jiyi.Agent.HTTPClient, :context_assemble, fn _state, request ->
      Agent.update(calls, &[{:context_assemble, request["task"]} | &1])
      {:ok, %{"assembled_context" => "", "sources" => []}}
    end)

    config =
      Config.new(
        agent_id: "harness-agent",
        session_id: "harness-session",
        api_key: "test-token",
        endpoint: "http://localhost:4001",
        transport: :http,
        llm: %{module: FakeLLM, behavior: :echo}
      )

    {:ok, pid} = Harness.start_link(config)

    assert {:ok, "ok"} = Harness.run(pid, "same task every time")
    assert {:ok, "ok"} = Harness.run(pid, "same task every time")

    recorded = Agent.get(calls, &Enum.reverse/1)

    assemble_tasks =
      Enum.filter(recorded, fn
        {:context_assemble, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:context_assemble, task} -> task end)

    first_turn = Enum.take(assemble_tasks, 1)
    second_turn = Enum.drop(assemble_tasks, 1)

    assert first_turn == ["same task every time"]
    assert second_turn == ["same task every time"]
  end

  test "targeted context_assemble runs after memory_write returns written" do
    {:ok, calls} = Agent.start(fn -> [] end)

    :meck.new(Jiyi.Agent.HTTPClient, [:passthrough])

    :meck.expect(Jiyi.Agent.HTTPClient, :memory_write, fn _state, request ->
      Agent.update(calls, &[{:memory_write, request} | &1])
      {:ok, %{"status" => "written", "id" => "semantic-1"}}
    end)

    :meck.expect(Jiyi.Agent.HTTPClient, :context_assemble, fn _state, request ->
      Agent.update(calls, &[{:context_assemble, request["task"]} | &1])
      {:ok, %{"assembled_context" => "refreshed context", "sources" => []}}
    end)

    config =
      Config.new(
        agent_id: "harness-agent",
        session_id: "harness-session",
        api_key: "test-token",
        endpoint: "http://localhost:4001",
        transport: :http,
        llm: %{module: FakeLLM, behavior: :memory_tool}
      )

    {:ok, pid} = Harness.start_link(config)

    assert {:ok, "done"} = Harness.run(pid, "remember the harness")

    recorded = Agent.get(calls, &Enum.reverse/1)

    assemble_tasks =
      Enum.filter(recorded, fn
        {:context_assemble, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:context_assemble, task} -> task end)

    assert "project uses harness" in assemble_tasks
  end
end
