defmodule Simulator.World.TravelTest do
  use ExUnit.Case, async: true

  alias Simulator.World.Travel

  describe "travel_time/2" do
    test "returns known distances" do
      assert {:ok, 100} = Travel.travel_time("earth-station", "mars-station")
      assert {:ok, 150} = Travel.travel_time("earth-station", "belt-outpost")
      assert {:ok, 80} = Travel.travel_time("mars-station", "belt-outpost")
    end

    test "distances are bidirectional" do
      assert {:ok, 100} = Travel.travel_time("mars-station", "earth-station")
      assert {:ok, 150} = Travel.travel_time("belt-outpost", "earth-station")
    end

    test "same location returns 0" do
      assert {:ok, 0} = Travel.travel_time("earth-station", "earth-station")
    end

    test "unknown route returns error" do
      assert {:error, :unknown_route} = Travel.travel_time("earth-station", "pluto")
    end
  end

  describe "fuel_cost/2" do
    test "calculates fuel consumed" do
      assert Travel.fuel_cost(10, 0.5) == 5.0
      assert Travel.fuel_cost(15, 0.5) == 7.5
      assert Travel.fuel_cost(0, 0.5) == 0.0
    end
  end

  describe "reachable_from/1" do
    test "returns other locations" do
      reachable = Travel.reachable_from("earth-station")
      assert "mars-station" in reachable
      assert "belt-outpost" in reachable
      refute "earth-station" in reachable
    end
  end
end
