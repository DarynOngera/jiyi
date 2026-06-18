defmodule Jiyi.Memory.ProceduralTest do
  use ExUnit.Case

  alias Jiyi.Memory.Procedural

  setup do
    tmp_dir =
      System.tmp_dir!() |> Path.join("jiyi-test-playbooks-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    investigate_dir = Path.join(tmp_dir, "investigate")
    File.mkdir_p!(investigate_dir)
    File.write!(Path.join(investigate_dir, "01-triage.md"), "# Triage\nCheck alerts.")
    File.write!(Path.join(investigate_dir, "02-escalate.md"), "# Escalate\nCall IR.")

    original_root = Application.get_env(:jiyi, :procedural_playbooks_root)
    Application.put_env(:jiyi, :procedural_playbooks_root, tmp_dir)

    on_exit(fn ->
      if original_root do
        Application.put_env(:jiyi, :procedural_playbooks_root, original_root)
      else
        Application.delete_env(:jiyi, :procedural_playbooks_root)
      end

      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  test "task_type_for_task/1 matches keywords" do
    assert Procedural.task_type_for_task("investigate alert") == "investigate"
    assert Procedural.task_type_for_task("handle incident") == "incident"
    assert Procedural.task_type_for_task("unknown task") == nil
  end

  test "playbooks_for_task/1 returns sorted markdown files for matching task" do
    paths = Procedural.playbooks_for_task("investigate alert")
    assert length(paths) == 2
    assert Enum.all?(paths, &String.ends_with?(&1, ".md"))
  end

  test "playbooks_for_task/1 returns empty list for unmatched task" do
    assert Procedural.playbooks_for_task("make coffee") == []
  end

  test "content_for_task/1 reads playbook contents" do
    contents = Procedural.content_for_task("investigate")
    assert length(contents) == 2
    assert Enum.any?(contents, &String.contains?(&1, "Check alerts"))
  end
end
