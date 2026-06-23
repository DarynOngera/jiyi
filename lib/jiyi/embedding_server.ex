defmodule Jiyi.EmbeddingServer do
  @moduledoc """
  Local BAAI/bge-base-en-v1.5 embedding server.

  Loads the model and tokenizer once at startup and serves embeddings through
  an Nx.Serving. Use Jiyi.EmbeddingServer.HTTP for the HTTP interface, or call
  embed/1 directly.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def serving do
    GenServer.call(__MODULE__, :serving, :infinity)
  end

  def embed(text) when is_binary(text) do
    %{embedding: tensor} = Nx.Serving.run(serving(), text)
    {:ok, Nx.to_list(tensor)}
  rescue
    e ->
      Logger.warning("Embedding inference failed: #{inspect(e)}")
      {:error, :inference_failed}
  end

  @impl true
  def init(_opts) do
    Process.set_label(__MODULE__)

    repo = Application.fetch_env!(:jiyi, :embedding_model_repo)

    Logger.info("Loading embedding model #{repo}...")

    {:ok, model_info} = Bumblebee.load_model({:hf, repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, repo})

    serving =
      Bumblebee.Text.TextEmbedding.text_embedding(model_info, tokenizer,
        output_attribute: :hidden_state,
        output_pool: :cls_token_pooling,
        embedding_processor: :l2_norm
      )

    Logger.info("Embedding model loaded.")

    {:ok, %{serving: serving}}
  end

  @impl true
  def handle_call(:serving, _from, %{serving: serving} = state) do
    {:reply, serving, state}
  end
end
