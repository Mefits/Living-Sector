defmodule Simulator.MetricsTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Metrics

  describe "snapshot/0" do
    test "returns a complete metrics map" do
      snapshot = Metrics.snapshot()

      assert is_map(snapshot.tick)
      assert is_number(snapshot.tick.avg_duration_us)
      assert is_number(snapshot.tick.ticks_per_second)

      assert is_map(snapshot.agents)
      assert is_integer(snapshot.agents.total)
      assert is_map(snapshot.agents.counts)
      assert is_list(snapshot.agents.stalled)

      assert is_map(snapshot.persistence)
    end
  end

  describe "record_tick_duration/1" do
    test "accumulates tick duration measurements" do
      Metrics.record_tick_duration(100)
      Metrics.record_tick_duration(200)
      Metrics.record_tick_duration(150)

      # Allow GenServer to process casts
      Process.sleep(10)

      snapshot = Metrics.snapshot()
      assert snapshot.tick.avg_duration_us > 0
      assert snapshot.tick.samples >= 3
    end
  end

  describe "record_flush_duration/1" do
    test "records persistence flush timing" do
      Metrics.record_flush_duration(5000)
      Process.sleep(10)

      snapshot = Metrics.snapshot()
      assert snapshot.persistence.last_flush_duration_us == 5000
    end
  end
end
