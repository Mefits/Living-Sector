defmodule Simulator.Agents.FactionAgentTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.{FacilityAgent, FactionAgent}

  @tax_interval 200 * Simulator.Simulation.Config.tick_multiplier()
  @subsidy_check_interval 30 * Simulator.Simulation.Config.tick_multiplier()

  defp start_facility(id, location, overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: id,
          name: id,
          location: location,
          docking_capacity: 4,
          services: [:refuel, :market],
          reserves: %{fuel: 500, food: 200},
          credits: 10_000,
          faction_id: "terran-authority"
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {FacilityAgent, config})

    pid
  end

  defp start_faction(overrides) do
    config =
      Map.merge(
        %{
          id: "faction-terran-authority",
          faction_id: "terran-authority",
          name: "Terran Authority",
          personality: %{profit: 0.4, safety: 0.9},
          treasury: 50_000,
          member_facilities: []
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {FactionAgent, config})

    pid
  end

  defp send_tick(pid, tick) do
    send(pid, {:tick, tick})
    :sys.get_state(pid)
  end

  describe "initialization" do
    test "starts with the configured treasury and member list" do
      pid =
        start_faction(%{treasury: 12_345, member_facilities: ["earth-station", "mars-station"]})

      state = FactionAgent.get_state(pid)
      assert state.treasury == 12_345
      assert state.member_facilities == ["earth-station", "mars-station"]
      assert state.faction_id == "terran-authority"
      assert MapSet.size(state.active_subsidies) == 0
    end

    test "subscribes to each member market's PubSub topic" do
      pid = start_faction(%{member_facilities: ["earth-station"]})

      Simulator.Events.broadcast("market:earth-station", :price_update, %{
        facility_id: "earth-station",
        prices: %{},
        supply: %{},
        demand: %{},
        shortage_ticks: %{fuel: 42},
        tick: 1
      })

      # PubSub delivery is async — yield until the message lands in the
      # faction's mailbox.
      Process.sleep(10)
      :sys.get_state(pid)

      state = FactionAgent.get_state(pid)
      assert state.shortage_cache["earth-station"].fuel == 42
    end
  end

  describe "tax sweep" do
    test "deducts the configured rate from member facilities into the treasury" do
      start_facility("facility-earth-station", "earth-station", %{credits: 100_000})

      pid =
        start_faction(%{
          treasury: 0,
          member_facilities: ["earth-station"]
        })

      state = send_tick(pid, @tax_interval)

      # With @tax_rate = 0.005 and a $1000 buffer:
      #   taxable = 100_000 - 1_000 = 99_000
      #   amount  = 99_000 * 0.005 = 495
      assert state.treasury == 495
    end

    test "collects nothing from a facility below the tax buffer" do
      start_facility("facility-earth-station", "earth-station", %{credits: 500})

      pid = start_faction(%{treasury: 0, member_facilities: ["earth-station"]})

      state = send_tick(pid, @tax_interval)

      assert state.treasury == 0
    end

    test "aggregates across multiple member facilities" do
      start_facility("facility-a", "a", %{credits: 20_000})
      start_facility("facility-b", "b", %{credits: 60_000})

      pid = start_faction(%{treasury: 0, member_facilities: ["a", "b"]})

      state = send_tick(pid, @tax_interval)

      # Expected: (20000-1000)*0.005 + (60000-1000)*0.005 = 95 + 295 = 390
      assert state.treasury == 390
    end
  end

  describe "subsidy posting" do
    test "does nothing when fewer than the required member facilities are short" do
      pid = start_faction(%{member_facilities: ["a", "b"]})

      # Only one facility short — below @min_facilities_short.
      Simulator.Events.broadcast("market:a", :price_update, %{
        facility_id: "a",
        prices: %{},
        supply: %{},
        demand: %{},
        shortage_ticks: %{ore: 200},
        tick: 1
      })

      Process.sleep(10)
      :sys.get_state(pid)
      state = send_tick(pid, @subsidy_check_interval)

      assert MapSet.size(state.active_subsidies) == 0
    end

    test "posts a subsidy when enough members are chronically short" do
      pid = start_faction(%{treasury: 100_000, member_facilities: ["a", "b", "c"]})

      # Two of three facilities well past the trigger threshold.
      for facility <- ["a", "b"] do
        Simulator.Events.broadcast("market:#{facility}", :price_update, %{
          facility_id: facility,
          prices: %{},
          supply: %{},
          demand: %{},
          shortage_ticks: %{ore: 80},
          tick: 1
        })
      end

      Process.sleep(10)
      :sys.get_state(pid)
      state = send_tick(pid, @subsidy_check_interval)

      assert MapSet.size(state.active_subsidies) == 1
      # Treasury drained by the subsidy payout.
      assert state.treasury < 100_000
    end

    test "does not post when treasury is depleted" do
      pid = start_faction(%{treasury: 100, member_facilities: ["a", "b"]})

      for facility <- ["a", "b"] do
        Simulator.Events.broadcast("market:#{facility}", :price_update, %{
          facility_id: facility,
          prices: %{},
          supply: %{},
          demand: %{},
          shortage_ticks: %{ore: 80},
          tick: 1
        })
      end

      Process.sleep(10)
      :sys.get_state(pid)
      state = send_tick(pid, @subsidy_check_interval)

      assert MapSet.size(state.active_subsidies) == 0
      assert state.treasury == 100
    end
  end
end
