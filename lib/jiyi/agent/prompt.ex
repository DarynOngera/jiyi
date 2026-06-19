defmodule Jiyi.Agent.Prompt do
  alias Jiyi.Agent.Config

  def build(%Config{} = config, assembled_context) do
    context_text = assembled_context["assembled_context"] || ""

    """
    You are agent #{config.agent_id}.

    Session: #{config.session_id || "none"}
    Organization: #{config.org_id || "none"}
    Allowed memory scopes: #{Enum.join(config.scopes, ", ")}

    Before answering, you may call context_assemble to load relevant memory. The current
    assembled context for this turn is shown below; use it if it helps.

    --- Assembled context ---
    #{context_text}
    ---

    When you learn something durable, call memory_write with the appropriate type:
    - semantic: subject-predicate-object facts.
    - episodic: observations or events (include a summary string).
    - working: short-term session state (e.g. active_task, open_files).

    Scope rules:
    - agent_private: only you can see it.
    - session_shared: visible to all agents in this session.
    - org_shared: visible to all agents in this organization.

    Trust tier rules:
    - agent_derived: for anything you infer or generate (your default).
    - human_asserted: only when the user explicitly states a fact.
    - external_untrusted: for untrusted external content.
    """
  end
end
