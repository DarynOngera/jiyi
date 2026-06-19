defmodule Jiyi.Agent.ToolsTest do
  use ExUnit.Case

  alias Jiyi.Agent.Tools

  test "memory_write tool declares required fields and enums" do
    tool = Tools.memory_write()

    assert tool["name"] == "memory_write"
    schema = tool["input_schema"]

    assert schema["required"] == ["type", "content", "provenance", "scope"]
    assert schema["properties"]["type"]["enum"] == ["semantic", "episodic", "working"]

    assert schema["properties"]["scope"]["enum"] == [
             "agent_private",
             "session_shared",
             "org_shared"
           ]
  end

  test "context_assemble tool declares required fields" do
    tool = Tools.context_assemble()

    assert tool["name"] == "context_assemble"
    assert tool["input_schema"]["required"] == ["task"]
  end
end
