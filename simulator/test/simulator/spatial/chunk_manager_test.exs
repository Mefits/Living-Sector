defmodule Simulator.Spatial.ChunkManagerTest do
  use ExUnit.Case

  alias Simulator.Spatial.{ChunkManager, Observer}

  setup do
    ChunkManager.reset()
    :ok
  end

  describe "register and tick divisor" do
    test "registered entity defaults to divisor 1" do
      ChunkManager.register_entity("ship-1", 0.0, 0.0)
      assert ChunkManager.tick_divisor_for("ship-1") == 1
    end

    test "unregistered entity returns divisor 1" do
      assert ChunkManager.tick_divisor_for("unknown") == 1
    end
  end

  describe "should_tick?/2" do
    test "unregistered agents always tick" do
      assert ChunkManager.should_tick?("unknown", 1)
      assert ChunkManager.should_tick?("unknown", 50)
    end

    test "entity near observer ticks every tick" do
      ChunkManager.register_entity("ship-1", 0.0, 0.0)

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: 0.0,
        y: 0.0,
        radius: 20.0
      })

      assert ChunkManager.should_tick?("ship-1", 1)
      assert ChunkManager.should_tick?("ship-1", 2)
      assert ChunkManager.should_tick?("ship-1", 99)
    end

    test "far entity with no nearby observer gets high divisor" do
      ChunkManager.register_entity("ship-far", 400.0, 400.0)

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: -200.0,
        y: -200.0,
        radius: 10.0
      })

      divisor = ChunkManager.tick_divisor_for("ship-far")
      assert divisor > 10, "Expected high divisor for far entity, got #{divisor}"
    end
  end

  describe "observer management" do
    test "adding an observer recalculates divisors" do
      ChunkManager.register_entity("ship-1", 0.0, 0.0)

      ChunkManager.recalculate()
      divisor_before = ChunkManager.tick_divisor_for("ship-1")
      assert divisor_before == 50

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: 0.0,
        y: 0.0,
        radius: 20.0
      })

      divisor_after = ChunkManager.tick_divisor_for("ship-1")
      assert divisor_after == 1
    end

    test "removing observer increases divisors" do
      ChunkManager.register_entity("ship-1", 0.0, 0.0)

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: 0.0,
        y: 0.0,
        radius: 20.0
      })

      assert ChunkManager.tick_divisor_for("ship-1") == 1

      ChunkManager.remove_observer("obs-1")
      divisor = ChunkManager.tick_divisor_for("ship-1")
      assert divisor == 50
    end

    test "list_observers returns all observers" do
      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: 0.0,
        y: 0.0,
        radius: 10.0
      })

      observers = ChunkManager.list_observers()
      assert length(observers) == 1
      assert hd(observers).id == "obs-1"
    end

    test "update_observer changes position" do
      ChunkManager.register_entity("ship-1", 200.0, 200.0)

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: -200.0,
        y: -200.0,
        radius: 10.0
      })

      far_divisor = ChunkManager.tick_divisor_for("ship-1")
      assert far_divisor > 10

      ChunkManager.update_observer("obs-1", %{x: 200.0, y: 200.0, radius: 20.0})
      near_divisor = ChunkManager.tick_divisor_for("ship-1")
      assert near_divisor == 1
    end
  end

  describe "position updates" do
    test "update_position moves entity" do
      ChunkManager.register_entity("ship-1", -200.0, -200.0)

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: 200.0,
        y: 200.0,
        radius: 20.0
      })

      ChunkManager.recalculate()
      far_divisor = ChunkManager.tick_divisor_for("ship-1")
      assert far_divisor > 10

      ChunkManager.update_position("ship-1", 200.0, 200.0)
      ChunkManager.recalculate()
      near_divisor = ChunkManager.tick_divisor_for("ship-1")
      assert near_divisor == 1
    end
  end

  describe "parent-child relationships" do
    test "children inherit parent divisor" do
      ChunkManager.register_entity("ship-1", 0.0, 0.0)
      ChunkManager.register_entity("crew-1", 0.0, 0.0, parent_id: "ship-1")

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: 0.0,
        y: 0.0,
        radius: 20.0
      })

      assert ChunkManager.tick_divisor_for("crew-1") == 1
    end
  end

  describe "chunk grid" do
    test "get_chunk_grid returns unified divisor map" do
      ChunkManager.register_entity("ship-1", 0.0, 0.0)

      ChunkManager.add_observer(%Observer{
        id: "obs-1",
        x: 0.0,
        y: 0.0,
        radius: 20.0
      })

      grid = ChunkManager.get_chunk_grid()
      assert is_map(grid)
      assert map_size(grid) > 0

      # Chunk containing (0,0) with bounds {-500,-500,1000,1000} chunk_size 10
      # col = floor((0-(-500))/10) = 50, row = 50
      center_chunk = {50, 50}
      assert Map.get(grid, center_chunk) == 1

      # Corner chunk should have high divisor
      corner_chunk = {0, 0}
      corner_divisor = Map.get(grid, corner_chunk)
      assert corner_divisor > 10
    end
  end
end
