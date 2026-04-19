defmodule Simulator.SaveGameTest do
  use Simulator.DataCase, async: false

  alias Simulator.Admin

  setup do
    # Clean up any save files lingering from prior runs so list_saves
    # + save_as assertions are deterministic.
    on_exit(fn -> cleanup_test_saves() end)
    :ok
  end

  describe "save/0" do
    test "flushes + returns current tick + flushed count" do
      assert {:ok, result} = Admin.save()
      assert is_map(result)
      assert is_integer(result.tick)
      assert is_integer(result.flushed)
      assert is_integer(result.duration_ms)
    end
  end

  describe "save_as/1" do
    test "rejects empty name" do
      assert {:error, :invalid_name} = Admin.save_as("")
      assert {:error, :invalid_name} = Admin.save_as("   ")
    end

    test "rejects path traversal attempts" do
      assert {:error, :invalid_name} = Admin.save_as("../evil")
      assert {:error, :invalid_name} = Admin.save_as("foo/../bar")
    end

    test "rejects a non-string argument" do
      assert {:error, :invalid_name} = Admin.save_as(nil)
      assert {:error, :invalid_name} = Admin.save_as(123)
    end

    test "cannot overwrite the active save" do
      active = active_save_name()
      assert {:error, :cannot_overwrite_active_save} = Admin.save_as(active)
    end

    test "copies the DB to a named slot" do
      name = "test_save_#{System.unique_integer([:positive])}"

      assert {:ok, save} = Admin.save_as(name)
      assert save.name == name
      assert save.filename == name <> ".db"
      assert File.exists?(save.path)
      assert save.size_bytes > 0
    end

    test "sanitizes weird characters but still copies" do
      raw = "test_Weird Name With Spaces!#{System.unique_integer([:positive])}"

      assert {:ok, save} = Admin.save_as(raw)
      # Every run-of-special becomes a single underscore and the result
      # is lowercased.
      assert save.name =~ ~r/^[a-z0-9_]+$/
      assert File.exists?(save.path)
    end
  end

  describe "list_saves/0" do
    test "lists the active save with active: true" do
      assert {:ok, saves} = Admin.list_saves()
      active = Enum.find(saves, & &1.active)
      assert active, "expected the active DB to appear in the listing"
      assert is_integer(active.size_bytes)
      assert %DateTime{} = active.modified_at
    end

    test "includes a newly-created save" do
      name = "test_listed_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Admin.save_as(name)

      assert {:ok, saves} = Admin.list_saves()
      found = Enum.find(saves, &(&1.name == name))
      assert found, "expected #{name} to appear in list_saves"
      refute found.active
    end
  end

  # --- Helpers ---

  defp active_save_name do
    Application.get_env(:simulator, Simulator.Repo)[:database]
    |> Path.basename(".db")
  end

  defp saves_dir do
    Application.get_env(:simulator, Simulator.Repo)[:database]
    |> Path.dirname()
  end

  defp cleanup_test_saves do
    for filename <- File.ls!(saves_dir()),
        String.starts_with?(filename, "test_"),
        String.ends_with?(filename, ".db") or
          String.ends_with?(filename, ".db-wal") or
          String.ends_with?(filename, ".db-shm") do
      File.rm!(Path.join(saves_dir(), filename))
    end
  rescue
    _ -> :ok
  end
end
