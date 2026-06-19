defmodule Jiyi.Agent.Tools do
  def context_assemble do
    %{
      "name" => "context_assemble",
      "description" => """
      Retrieve ranked context from Jiyi memory stores before answering.

      Use this at the start of each turn to load relevant facts, events, working memory,
      and procedural playbooks for the current agent/session.
      """,
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "task" => %{
            "type" => "string",
            "description" => "The current task or user request."
          },
          "token_budget" => %{
            "type" => "integer",
            "description" => "Maximum tokens to return. Defaults to 4000."
          },
          "memory_scopes" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Scopes to include: agent_private, session_shared, org_shared."
          }
        },
        "required" => ["task"]
      }
    }
  end

  def memory_write do
    %{
      "name" => "memory_write",
      "description" => """
      Persist a memory to Jiyi.

      Choose the memory type based on content shape:
      - semantic: subject-predicate-object facts.
      - episodic: observations or events as a summary string.
      - working: short-term session state such as active_task or open_files.

      Scope controls visibility:
      - agent_private: only this agent can see it.
      - session_shared: visible to any agent with the same session_id.
      - org_shared: visible to any agent in the same org_id.

      Trust tier:
      - agent_derived: for anything you infer or generate (default).
      - human_asserted: only when the user explicitly states a fact.
      - external_untrusted: for untrusted external content (will be quarantined).
      """,
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "type" => %{
            "type" => "string",
            "enum" => ["semantic", "episodic", "working"],
            "description" => "Kind of memory to write."
          },
          "content" => %{
            "type" => "object",
            "description" => """
            Type-dependent content. semantic: {subject, predicate, object}.
            episodic: {summary}. working: any flat map.
            """
          },
          "provenance" => %{
            "type" => "object",
            "properties" => %{
              "source" => %{"type" => "string"},
              "ingestion_method" => %{"type" => "string"},
              "trust_tier" => %{
                "type" => "string",
                "enum" => ["human_asserted", "agent_derived", "external_untrusted"]
              }
            },
            "required" => ["source", "ingestion_method", "trust_tier"]
          },
          "scope" => %{
            "type" => "string",
            "enum" => ["agent_private", "session_shared", "org_shared"],
            "description" => "Visibility scope."
          }
        },
        "required" => ["type", "content", "provenance", "scope"]
      }
    }
  end
end
