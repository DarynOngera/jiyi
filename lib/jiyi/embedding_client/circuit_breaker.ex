defmodule Jiyi.EmbeddingClient.CircuitBreaker do
  @moduledoc """
  Circuit breaker for the local embedding endpoint.
  """

  use GenServer

  require Logger

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def embed(text) when is_binary(text) do
    GenServer.call(__MODULE__, {:embed, text})
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  @impl true
  def init(_init_arg) do
    Process.set_label(__MODULE__)

    {:ok,
     %{
       state: :closed,
       failures: 0,
       threshold: Application.fetch_env!(:jiyi, :circuit_breaker_threshold),
       cooldown_ms: Application.fetch_env!(:jiyi, :circuit_breaker_cooldown_ms),
       last_failure: nil
     }}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call({:embed, text}, _from, %{state: :open} = state) do
    if half_open?(state) do
      new_state = %{state | state: :half_open}
      {reply, new_state} = probe(text, new_state)
      {:reply, reply, new_state}
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end

  def handle_call({:embed, text}, _from, %{state: :half_open} = state) do
    {reply, new_state} = probe(text, state)
    {:reply, reply, new_state}
  end

  def handle_call({:embed, text}, _from, %{state: :closed} = state) do
    case call_embedding_endpoint(text) do
      {:ok, vector} ->
        new_state = %{state | failures: 0, last_failure: nil}
        {:reply, {:ok, vector}, new_state}

      {:error, reason} ->
        failures = state.failures + 1

        new_state =
          if failures >= state.threshold do
            emit_state_change(:closed, :open)
            %{state | state: :open, failures: failures, last_failure: now_ms()}
          else
            %{state | failures: failures, last_failure: now_ms()}
          end

        {:reply, {:error, reason}, new_state}
    end
  end

  defp probe(text, state) do
    case call_embedding_endpoint(text) do
      {:ok, vector} ->
        emit_state_change(state.state, :closed)
        {{:ok, vector}, %{state | state: :closed, failures: 0, last_failure: nil}}

      {:error, reason} ->
        emit_state_change(state.state, :open)

        {{:error, reason},
         %{state | state: :open, failures: state.threshold, last_failure: now_ms()}}
    end
  end

  defp half_open?(%{last_failure: nil}), do: false

  defp half_open?(%{last_failure: last_failure, cooldown_ms: cooldown_ms}) do
    now_ms() - last_failure >= cooldown_ms
  end

  defp call_embedding_endpoint(text) do
    endpoint = Application.fetch_env!(:jiyi, :embedding_endpoint)

    payload = Jason.encode!(%{text: text})

    headers = [{"content-type", "application/json"}]

    case Finch.build(:post, endpoint, headers, payload)
         |> Finch.request(Jiyi.Finch) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"embedding" => vector}} when is_list(vector) ->
            {:ok, vector}

          {:ok, vector} when is_list(vector) ->
            {:ok, vector}

          _ ->
            {:error, :invalid_response}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning("Embedding call failed: #{inspect(e)}")
      {:error, :request_failed}
  end

  defp emit_state_change(from, to) do
    :telemetry.execute([:jiyi, :circuit_breaker, :state_change], %{count: 1}, %{
      from: from,
      to: to
    })
  end

  defp now_ms do
    System.monotonic_time(:millisecond)
  end
end
