defmodule Jiyi.Repo do
  use Ecto.Repo,
    otp_app: :jiyi,
    adapter: Ecto.Adapters.Postgres,
    types: Jiyi.PostgrexTypes
end
