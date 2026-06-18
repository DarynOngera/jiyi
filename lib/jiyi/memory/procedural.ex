defmodule Jiyi.Memory.Procedural do
  @moduledoc """
  Git-backed procedural memory.

  Procedural memories are static instructions stored as markdown files under
  priv/playbooks/<task_type>/*.md. They are read at assembly time, not written
  through the memory/write API.
  """

  @default_task_types %{
    "investigate" => "investigate",
    "alert" => "investigate",
    "incident" => "incident",
    "deploy" => "deploy",
    "release" => "deploy",
    "test" => "test",
    "review" => "review",
    "code" => "code",
    "refactor" => "code"
  }

  def content_for_task(task) when is_binary(task) do
    task
    |> playbooks_for_task()
    |> Enum.map(&File.read!/1)
  end

  def content_for_task(_), do: []

  def playbooks_for_task(task) when is_binary(task) do
    case task_type_for_task(task) do
      nil ->
        []

      task_type ->
        root()
        |> Path.join(task_type)
        |> Path.join("*.md")
        |> Path.wildcard()
        |> Enum.sort()
    end
  end

  def playbooks_for_task(_), do: []

  def task_type_for_task(task) when is_binary(task) do
    task_lower = String.downcase(task)

    @default_task_types
    |> Enum.find(fn {keyword, _type} -> String.contains?(task_lower, keyword) end)
    |> case do
      nil -> nil
      {_keyword, type} -> type
    end
  end

  def task_type_for_task(_), do: nil

  defp root do
    Application.get_env(:jiyi, :procedural_playbooks_root, default_root())
  end

  defp default_root do
    :code.priv_dir(:jiyi)
    |> Path.join("playbooks")
  end
end
