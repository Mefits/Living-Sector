defmodule Simulator.AI.BehaviorTreeTest do
  use ExUnit.Case, async: true

  alias Simulator.AI.BehaviorTree, as: BT

  describe "action node" do
    test "succeeds immediately" do
      node = BT.action(:dock, fn bb -> {:success, Map.put(bb, :docked, true)} end)
      {status, _node, bb} = BT.tick(node, %{})

      assert status == :success
      assert bb.docked == true
    end

    test "returns running" do
      node = BT.action(:travel, fn bb -> {:running, bb} end)
      {status, _node, _bb} = BT.tick(node, %{})

      assert status == :running
    end

    test "fails" do
      node = BT.action(:dock, fn bb -> {:failure, bb} end)
      {status, _node, _bb} = BT.tick(node, %{})

      assert status == :failure
    end
  end

  describe "condition node" do
    test "succeeds when predicate is true" do
      node = BT.condition(:has_fuel, fn bb -> bb.fuel > 10 end)
      {status, _node, _bb} = BT.tick(node, %{fuel: 50})

      assert status == :success
    end

    test "fails when predicate is false" do
      node = BT.condition(:has_fuel, fn bb -> bb.fuel > 10 end)
      {status, _node, _bb} = BT.tick(node, %{fuel: 5})

      assert status == :failure
    end
  end

  describe "sequence node" do
    test "executes children in order" do
      node =
        BT.sequence([
          BT.action(:step1, fn bb -> {:success, Map.put(bb, :step1, true)} end),
          BT.action(:step2, fn bb -> {:success, Map.put(bb, :step2, true)} end),
          BT.action(:step3, fn bb -> {:success, Map.put(bb, :step3, true)} end)
        ])

      # Tick 1: step1 succeeds, moves to step2
      {status1, node, bb} = BT.tick(node, %{})
      assert status1 == :running
      assert bb.step1 == true

      # Tick 2: step2 succeeds, moves to step3
      {status2, node, bb} = BT.tick(node, bb)
      assert status2 == :running
      assert bb.step2 == true

      # Tick 3: step3 succeeds, sequence complete
      {status3, _node, bb} = BT.tick(node, bb)
      assert status3 == :success
      assert bb.step3 == true
    end

    test "fails on first child failure" do
      node =
        BT.sequence([
          BT.action(:ok, fn bb -> {:success, bb} end),
          BT.action(:fail, fn bb -> {:failure, bb} end),
          BT.action(:never, fn bb -> {:success, Map.put(bb, :reached, true)} end)
        ])

      {_, node, bb} = BT.tick(node, %{})
      {status, _node, bb} = BT.tick(node, bb)

      assert status == :failure
      refute Map.has_key?(bb, :reached)
    end

    test "pauses on running child" do
      counter = :counters.new(1, [:atomics])

      node =
        BT.sequence([
          BT.action(:wait, fn bb ->
            :counters.add(counter, 1, 1)
            count = :counters.get(counter, 1)

            if count >= 3 do
              {:success, Map.put(bb, :waited, true)}
            else
              {:running, bb}
            end
          end),
          BT.action(:after, fn bb -> {:success, Map.put(bb, :done, true)} end)
        ])

      # Tick 1: running
      {s1, node, bb} = BT.tick(node, %{})
      assert s1 == :running

      # Tick 2: still running
      {s2, node, bb} = BT.tick(node, bb)
      assert s2 == :running

      # Tick 3: wait succeeds, moves to after
      {s3, node, bb} = BT.tick(node, bb)
      assert s3 == :running
      assert bb.waited == true

      # Tick 4: after succeeds, sequence complete
      {s4, _node, bb} = BT.tick(node, bb)
      assert s4 == :success
      assert bb.done == true
    end
  end

  describe "selector node" do
    test "succeeds on first successful child" do
      node =
        BT.selector([
          BT.action(:try1, fn bb -> {:failure, bb} end),
          BT.action(:try2, fn bb -> {:success, Map.put(bb, :winner, :try2)} end),
          BT.action(:try3, fn bb -> {:success, Map.put(bb, :winner, :try3)} end)
        ])

      {status, _node, bb} = BT.tick(node, %{})
      assert status == :success
      assert bb.winner == :try2
    end

    test "fails when all children fail" do
      node =
        BT.selector([
          BT.action(:a, fn bb -> {:failure, bb} end),
          BT.action(:b, fn bb -> {:failure, bb} end)
        ])

      {status, _node, _bb} = BT.tick(node, %{})
      assert status == :failure
    end

    test "returns running when a child returns running" do
      node =
        BT.selector([
          BT.action(:fail, fn bb -> {:failure, bb} end),
          BT.action(:busy, fn bb -> {:running, bb} end)
        ])

      {status, _node, _bb} = BT.tick(node, %{})
      assert status == :running
    end
  end

  describe "current_action/1" do
    test "returns the name of the active node in a sequence" do
      node =
        BT.sequence([
          BT.action(:dock, fn bb -> {:success, bb} end),
          BT.action(:buy, fn bb -> {:success, bb} end)
        ])

      assert BT.current_action(node) == :dock

      {_, node, _} = BT.tick(node, %{})
      assert BT.current_action(node) == :buy
    end
  end

  describe "trade run behavior tree" do
    test "executes a full trade run sequence" do
      trade_run =
        BT.sequence([
          BT.action(:dock_origin, fn bb -> {:success, Map.put(bb, :docked, true)} end),
          BT.action(:refuel, fn bb -> {:success, Map.put(bb, :fueled, true)} end),
          BT.action(:buy, fn bb -> {:success, Map.put(bb, :cargo, :ore)} end),
          BT.action(:undock, fn bb -> {:success, Map.put(bb, :docked, false)} end),
          BT.action(:travel, fn bb -> {:success, Map.put(bb, :location, :dest)} end),
          BT.action(:dock_dest, fn bb -> {:success, Map.put(bb, :docked, true)} end),
          BT.action(:sell, fn bb -> {:success, Map.put(bb, :cargo, nil)} end),
          BT.action(:refuel_dest, fn bb -> {:success, Map.put(bb, :fueled, true)} end),
          BT.action(:undock_dest, fn bb -> {:success, Map.put(bb, :docked, false)} end)
        ])

      # Run through the entire sequence
      {final_status, _tree, final_bb} =
        Enum.reduce(1..9, {:running, trade_run, %{}}, fn _tick, {_status, tree, bb} ->
          BT.tick(tree, bb)
        end)

      assert final_status == :success
      assert final_bb.cargo == nil
      assert final_bb.location == :dest
      assert final_bb.docked == false
    end
  end
end
