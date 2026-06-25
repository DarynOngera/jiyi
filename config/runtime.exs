import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :jiyi, Jiyi.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :jiyi,
    http_port: String.to_integer(System.get_env("JIYI_HTTP_PORT") || "4000"),
    api_token: System.get_env("JIYI_API_TOKEN") || raise("JIYI_API_TOKEN is missing")

  config :jiyi,
    embedding_server_enabled: System.get_env("JIYI_EMBEDDING_SERVER_ENABLED", "false") == "true",
    embedding_server_port:
      String.to_integer(System.get_env("JIYI_EMBEDDING_SERVER_PORT", "8001")),
    embedding_endpoint: System.get_env("JIYI_EMBEDDING_ENDPOINT", "http://localhost:8001/embed")
end

config :jiyi,
  embedding_server_enabled: System.get_env("JIYI_EMBEDDING_SERVER_ENABLED", "false") == "true",
  embedding_server_port: String.to_integer(System.get_env("JIYI_EMBEDDING_SERVER_PORT", "8001"))

if endpoint = System.get_env("JIYI_EMBEDDING_ENDPOINT") do
  config :jiyi, :embedding_endpoint, endpoint
end

if adapter = System.get_env("JIYI_MCP_CLIENT_ADAPTER") do
  config :jiyi, :mcp_client_adapter, String.to_existing_atom(adapter)
end

if mod = System.get_env("JIYI_MCP_SERVER_MODULE") do
  config :jiyi, :mcp_server_module, String.to_existing_atom(mod)
end
