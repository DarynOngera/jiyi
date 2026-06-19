defmodule Jiyi.Agent.LLM do
  @callback chat(messages :: [map()], tools :: [map()], config :: map()) ::
              {:ok, %{content: String.t() | nil, tool_calls: [map()]}} | {:error, term()}
end
