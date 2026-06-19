defmodule Jiyi.Agent.HTTPClient do
  @behaviour Jiyi.Agent.Client

  alias Jiyi.Agent.Config
  alias Jiyi.Agent.Tools

  @impl true
  def init(%Config{} = config), do: {:ok, config}

  @impl true
  def context_assemble(%Config{} = config, request) do
    body = Map.merge(base_body(config), request)
    post(config, "/context/assemble", body)
  end

  @impl true
  def memory_write(%Config{} = config, request) do
    body = Map.merge(base_body(config), request)
    post(config, "/memory/write", body)
  end

  @impl true
  def tools, do: [Tools.context_assemble(), Tools.memory_write()]

  defp post(%Config{} = config, path, body) do
    url = config.endpoint <> path

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer " <> config.api_key}
    ]

    payload = Jason.encode!(body)

    case Finch.build(:post, url, headers, payload) |> Finch.request(Jiyi.Finch) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, Jason.decode!(resp_body)}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, %{status: status, body: Jason.decode!(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_body(%Config{} = config) do
    %{"agent_id" => config.agent_id}
    |> put_if("session_id", config.session_id)
    |> put_if("org_id", config.org_id)
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
