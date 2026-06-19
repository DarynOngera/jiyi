defmodule Jiyi.Agent.Config do
  defstruct [
    :agent_id,
    :session_id,
    :org_id,
    :endpoint,
    :transport,
    :api_key,
    :scopes,
    :token_budget,
    :llm
  ]

  @type t :: %__MODULE__{
          agent_id: String.t(),
          session_id: String.t() | nil,
          org_id: String.t() | nil,
          endpoint: String.t() | nil,
          transport: :http | :mcp_stdio | :mcp_http,
          api_key: String.t() | nil,
          scopes: [String.t()],
          token_budget: non_neg_integer(),
          llm: map() | nil
        }

  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)
    transport = attrs[:transport] || attrs["transport"] || :http

    %__MODULE__{
      agent_id: get_attr(attrs, :agent_id),
      session_id: get_attr(attrs, :session_id),
      org_id: get_attr(attrs, :org_id),
      endpoint: get_attr(attrs, :endpoint) || default_endpoint(transport),
      transport: transport,
      api_key: get_attr(attrs, :api_key),
      scopes: get_attr(attrs, :scopes) || ["agent_private", "session_shared", "org_shared"],
      token_budget: get_attr(attrs, :token_budget) || 4000,
      llm: get_attr(attrs, :llm)
    }
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp default_endpoint(:http), do: "http://localhost:4000"
  defp default_endpoint(:mcp_http), do: "http://localhost:4001"
  defp default_endpoint(:mcp_stdio), do: nil
end
