import Config

config :jiyi, Jiyi.Repo,
  username: System.get_env("JIYI_DB_USER") || "postgres",
  password: System.get_env("JIYI_DB_PASSWORD") || "postgres",
  hostname: System.get_env("JIYI_DB_HOST") || "localhost",
  database: System.get_env("JIYI_DB_NAME") || "jiyi_dev",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  show_sensitive_data_on_connection_error: true

config :jiyi, :http_port, String.to_integer(System.get_env("JIYI_TEST_HTTP_PORT") || "4001")
config :jiyi, :api_token, "test-token"
config :jiyi, :mcp_transport, {:streamable_http, port: 4003}

config :logger, :console, level: :warning
