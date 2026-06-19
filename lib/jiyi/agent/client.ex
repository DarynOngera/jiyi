defmodule Jiyi.Agent.Client do
  alias Jiyi.Agent.Config

  @callback init(Config.t()) :: {:ok, term()} | {:error, term()}
  @callback context_assemble(state :: term(), request :: map()) ::
              {:ok, map()} | {:error, term()}
  @callback memory_write(state :: term(), request :: map()) :: {:ok, map()} | {:error, term()}
  @callback tools() :: [map()]
end
