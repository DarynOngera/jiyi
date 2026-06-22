defmodule Jiyi.Anomaly.ReferenceStore do
  @moduledoc """
  Named GenServer that caches anomaly detector reference vectors in memory.

  Vectors are loaded once at startup from :anomaly_reference_injections config
  and can be reloaded at runtime via reload/0.
  """

  use GenServer

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def vectors do
    GenServer.call(__MODULE__, :vectors)
  end

  def reload do
    GenServer.cast(__MODULE__, :reload)
  end

  @impl true
  def init(_init_arg) do
    Process.set_label(__MODULE__)
    {:ok, load_vectors()}
  end

  @impl true
  def handle_call(:vectors, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:reload, _state) do
    {:noreply, load_vectors()}
  end

  defp load_vectors do
    phrases = Application.get_env(:jiyi, :anomaly_reference_injections, [])

    Enum.flat_map(phrases, fn phrase ->
      case embed_phrase(phrase) do
        {:ok, vector} -> [vector]
        {:error, _} -> []
      end
    end)
  end

  defp embed_phrase(phrase) do
    Jiyi.EmbeddingClient.CircuitBreaker.embed(phrase)
  catch
    :exit, _ -> {:error, :not_available}
  end
end
