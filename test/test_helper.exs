ExUnit.start()

if Process.whereis(Jiyi.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(Jiyi.Repo, :manual)
end
