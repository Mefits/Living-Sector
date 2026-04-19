defmodule Simulator.AgentSnapshotsTest do
  use ExUnit.Case, async: false

  alias Simulator.AgentSnapshots

  setup do
    AgentSnapshots.init()
    AgentSnapshots.reset()
    :ok
  end

  describe "put/list/get/delete" do
    test "stores and retrieves a snapshot by type + id" do
      :ok = AgentSnapshots.put(:ship, "ship-test-1", %{credits: 100, fuel: 50})

      assert AgentSnapshots.get(:ship, "ship-test-1") == %{credits: 100, fuel: 50}
    end

    test "get/2 returns nil for unknown ids" do
      assert AgentSnapshots.get(:ship, "ship-nonexistent") == nil
    end

    test "list/1 returns only snapshots of the given type" do
      AgentSnapshots.put(:ship, "s1", %{credits: 1})
      AgentSnapshots.put(:ship, "s2", %{credits: 2})
      AgentSnapshots.put(:facility, "f1", %{credits: 99})

      ships = AgentSnapshots.list(:ship) |> Enum.sort_by(& &1.credits)
      assert ships == [%{credits: 1}, %{credits: 2}]

      assert AgentSnapshots.list(:facility) == [%{credits: 99}]
    end

    test "list/1 returns empty list for a type with no snapshots" do
      assert AgentSnapshots.list(:population) == []
    end

    test "put/3 replaces an existing snapshot" do
      AgentSnapshots.put(:ship, "ship-a", %{credits: 100})
      AgentSnapshots.put(:ship, "ship-a", %{credits: 200})

      assert AgentSnapshots.get(:ship, "ship-a") == %{credits: 200}
      assert AgentSnapshots.list(:ship) == [%{credits: 200}]
    end

    test "delete/2 removes a snapshot" do
      AgentSnapshots.put(:ship, "ship-doomed", %{credits: 1})
      AgentSnapshots.delete(:ship, "ship-doomed")

      assert AgentSnapshots.get(:ship, "ship-doomed") == nil
      assert AgentSnapshots.list(:ship) == []
    end

    test "delete/2 on a missing id is a no-op" do
      assert :ok = AgentSnapshots.delete(:ship, "ship-never-existed")
    end
  end

  describe "reset/0" do
    test "wipes all snapshots across types" do
      AgentSnapshots.put(:ship, "s1", %{})
      AgentSnapshots.put(:facility, "f1", %{})
      AgentSnapshots.put(:market, "m1", %{})

      AgentSnapshots.reset()

      assert AgentSnapshots.list(:ship) == []
      assert AgentSnapshots.list(:facility) == []
      assert AgentSnapshots.list(:market) == []
    end
  end
end
