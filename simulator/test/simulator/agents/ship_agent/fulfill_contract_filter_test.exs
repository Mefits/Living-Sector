defmodule Simulator.Agents.ShipAgent.FulfillContractFilterTest do
  use ExUnit.Case, async: true

  alias Simulator.AI.Considerations
  alias Simulator.Agents.ShipAgent.Goals

  describe "Considerations.supply_contract?/1" do
    test "true for a classic supply contract (commodity, no reserve_id)" do
      assert Considerations.supply_contract?(%{commodity: "ore", payment: 500})
    end

    test "false for a delivery contract (has reserve_id)" do
      refute Considerations.supply_contract?(%{
               commodity: "ore",
               reserve_id: "reserve-42",
               delivery_fee: 300
             })
    end

    test "false for a passenger contract (no commodity)" do
      refute Considerations.supply_contract?(%{
               contract_type: "passenger_transport",
               passenger_count: 12,
               payment: 400
             })
    end

    test "false for a crew mission (no commodity)" do
      refute Considerations.supply_contract?(%{
               contract_type: "crew_mission",
               required_skill: "combat",
               payment: 1500
             })
    end
  end

  describe "contract_opportunity/1 filters by supply-contract shape" do
    test "returns 0 when only passenger/crew contracts are posted" do
      state = %{
        fuel_consumption_rate: 0.05,
        available_contracts: [
          passenger_contract(payment: 1000),
          crew_mission_contract(payment: 2000)
        ]
      }

      {value, :profit} = Considerations.contract_opportunity(state)
      assert value == 0.0
    end

    test "scores the supply contract and ignores higher-paying non-supply ones" do
      state = %{
        fuel_consumption_rate: 0.05,
        available_contracts: [
          # Much higher payment — but wrong type; should be ignored.
          passenger_contract(payment: 9000, distance: 30),
          # Lower payment — but this is the one fulfill_contract can handle.
          supply_contract(payment: 2000, distance: 40)
        ]
      }

      {value, :profit} = Considerations.contract_opportunity(state)
      assert value > 0.0
    end

    test "returns 0 with no contracts at all" do
      state = %{fuel_consumption_rate: 0.05, available_contracts: []}
      {value, :profit} = Considerations.contract_opportunity(state)
      assert value == 0.0
    end
  end

  describe "build_tree(:fulfill_contract, ...)" do
    test "returns idle BT when the only contracts are non-supply" do
      state = base_ship_state()
      state = %{state | available_contracts: [passenger_contract(payment: 5000)]}

      bt = Goals.build_tree(:fulfill_contract, state, 0)
      # Idle BT is a single action node: `{:action, :idle, _fun}`.
      assert match?({:action, :idle, _}, bt)
    end

    test "builds the supply-contract sequence when one is available" do
      state = base_ship_state()

      state = %{
        state
        | available_contracts: [
            passenger_contract(payment: 9000),
            supply_contract(payment: 2000, commodity: "fuel")
          ]
      }

      bt = Goals.build_tree(:fulfill_contract, state, 0)
      # Full sequence BT: `{:sequence, [children...], 0}`. Confirms we
      # found a supply contract and did NOT fall through to idle.
      assert match?({:sequence, [_ | _], _}, bt)
    end

    test "returns idle BT with empty available_contracts" do
      state = base_ship_state()
      state = %{state | available_contracts: []}

      bt = Goals.build_tree(:fulfill_contract, state, 0)
      assert match?({:action, :idle, _}, bt)
    end
  end

  # --- helpers ---

  defp base_ship_state do
    %{
      location: "earth-station",
      cargo: %{},
      cargo_capacity: 500,
      fuel: 80.0,
      fuel_capacity: 100.0,
      fuel_consumption_rate: 0.05,
      credits: 3000,
      faction_id: "independent",
      memory: %{known_prices: %{}, visited: []},
      available_contracts: []
    }
  end

  defp supply_contract(opts) do
    %{
      id: "contract-supply-#{System.unique_integer([:positive])}",
      contract_type: "supply",
      commodity: Keyword.get(opts, :commodity, "ore"),
      quantity_remaining: 50,
      payment: Keyword.get(opts, :payment, 1000),
      distance: Keyword.get(opts, :distance, 50),
      destination_location: "mars-station",
      faction_id: "independent"
    }
  end

  defp passenger_contract(opts) do
    %{
      id: "contract-pax-#{System.unique_integer([:positive])}",
      contract_type: "passenger_transport",
      source_location: "luna-base",
      destination_location: "earth-station",
      passenger_count: 16,
      quantity: 16,
      payment: Keyword.get(opts, :payment, 400),
      distance: Keyword.get(opts, :distance, 80),
      faction_id: "independent"
    }
  end

  defp crew_mission_contract(opts) do
    %{
      id: "contract-crew-#{System.unique_integer([:positive])}",
      contract_type: "crew_mission",
      source_location: "earth-station",
      destination_location: "earth-station",
      required_skill: "engineering",
      duration_ticks: 25,
      skill_gain: 2,
      payment: Keyword.get(opts, :payment, 1500),
      distance: 0,
      faction_id: "independent"
    }
  end
end
