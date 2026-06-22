defmodule Jiyi.Agent.MCP.Adapter do
  @moduledoc """
  Behaviour for client-side MCP adapters.

  Implementations wrap a specific MCP client framework (e.g. Anubis) and are
  selected at runtime via the :mcp_client_adapter application config.
  """

  @callback start_link(opts :: keyword()) :: {:ok, pid()} | {:error, term()}
  @callback await_ready(name :: term(), timeout_ms :: non_neg_integer()) ::
              :ok | {:error, term()}
  @callback call_tool(name :: term(), tool :: String.t(), args :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback build_transport(config :: Jiyi.Agent.Config.t()) :: term()
end
