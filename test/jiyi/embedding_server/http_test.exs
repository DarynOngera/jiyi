defmodule Jiyi.EmbeddingServer.HTTPTest do
  use ExUnit.Case

  alias Jiyi.EmbeddingServer.HTTP

  setup do
    vector = [0.1] ++ List.duplicate(0.0, 767)

    :meck.expect(Jiyi.EmbeddingServer, :embed, fn _ -> {:ok, vector} end)

    on_exit(fn ->
      try do
        :meck.unload(Jiyi.EmbeddingServer)
      rescue
        _ -> :ok
      end
    end)

    %{vector: vector}
  end

  test "POST /embed returns the embedding vector", %{vector: vector} do
    conn =
      :post
      |> Plug.Test.conn("/embed", Jason.encode!(%{"text" => "hello world"}))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> HTTP.call([])

    assert conn.status == 200
    assert %{"embedding" => ^vector} = Jason.decode!(conn.resp_body)
  end

  test "POST /embed with missing text returns 400" do
    conn =
      :post
      |> Plug.Test.conn("/embed", Jason.encode!(%{"invalid" => "payload"}))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> HTTP.call([])

    assert conn.status == 400
  end

  test "unknown path returns 404" do
    conn =
      :get
      |> Plug.Test.conn("/unknown")
      |> HTTP.call([])

    assert conn.status == 404
  end
end
