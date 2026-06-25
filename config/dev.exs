import Config

config :jiyi, Jiyi.Repo,
  username: System.get_env("JIYI_DB_USER") || "postgres",
  password: System.get_env("JIYI_DB_PASSWORD") || "postgres",
  hostname: System.get_env("JIYI_DB_HOST") || "localhost",
  database: System.get_env("JIYI_DB_NAME") || "jiyi_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  queue_target: 50,
  queue_interval: 1000

config :logger, :console, level: :debug
