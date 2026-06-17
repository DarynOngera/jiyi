defmodule JiyiTest do
  use ExUnit.Case
  doctest Jiyi

  test "public API is loadable" do
    assert function_exported?(Jiyi, :write_memory, 1)
    assert function_exported?(Jiyi, :assemble_context, 1)
  end
end
