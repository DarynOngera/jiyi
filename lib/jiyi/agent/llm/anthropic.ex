defmodule Jiyi.Agent.LLM.Anthropic do
  @behaviour Jiyi.Agent.LLM

  @api_url "https://api.anthropic.com/v1/messages"

  @impl true
  def chat(messages, tools, config) do
    api_key = config[:api_key] || raise ArgumentError, "Anthropic API key is required"
    model = config[:model] || "claude-sonnet-4-20250514"

    body =
      %{
        model: model,
        max_tokens: config[:max_tokens] || 4096,
        messages: messages,
        tools: Enum.map(tools, &to_anthropic_tool/1)
      }
      |> put_if(:system, config[:system_prompt])
      |> put_if(:tool_choice, config[:tool_choice])

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    with {:ok, %{status: 200, body: resp}} <-
           Finch.build(:post, @api_url, headers, Jason.encode!(body))
           |> Finch.request(Jiyi.Finch),
         {:ok, decoded} <- Jason.decode(resp) do
      content_blocks = decoded["content"] || []

      text =
        Enum.find_value(content_blocks, fn
          %{"type" => "text", "text" => t} -> t
          _ -> nil
        end)

      tool_calls =
        Enum.flat_map(content_blocks, fn
          %{"type" => "tool_use", "id" => id, "name" => name, "input" => input} ->
            [%{id: id, name: name, arguments: input}]

          _ ->
            []
        end)

      {:ok, %{content: text, tool_calls: tool_calls}}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: Jason.decode!(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp to_anthropic_tool(%{
         "name" => name,
         "description" => description,
         "input_schema" => schema
       }) do
    %{
      name: name,
      description: description,
      input_schema: schema
    }
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
