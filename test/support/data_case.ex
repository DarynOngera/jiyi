defmodule Jiyi.DataCase do
  @moduledoc """
  Test case for database-backed tests.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Jiyi.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Jiyi.DataCase
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Jiyi.Repo)

    unless tags[:async] do
      Sandbox.mode(Jiyi.Repo, {:shared, self()})
    end

    :ok
  end
end
