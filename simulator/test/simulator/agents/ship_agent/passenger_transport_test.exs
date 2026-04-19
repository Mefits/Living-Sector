defmodule Simulator.Agents.ShipAgent.PassengerTransportTest do
  use ExUnit.Case, async: true

  alias Simulator.AI.{Considerations, Personality, Utility}
  alias Simulator.Agents.ShipAgent.Goals

  describe "courier archetype" do
    test "has prefer_goals bonus on passenger transport" do
      p = Personality.courier()
      assert p.prefer_goals[:fulfill_passenger_transport] > 0.0
      assert p.prefer_goals[:fulfill_delivery] > 0.0
    end

    test "courier is included in the random_ship_personality pool" do
      # Pull a bunch and assert at least one courier shows up. 100 rolls
      # over 7 archetypes makes a false-positive ~10^-7.
      personalities = for _ <- 1..100, do: Personality.random_ship_personality()

      assert Enum.any?(personalities, fn p ->
               Map.get(p[:prefer_goals] || %{}, :fulfill_passenger_transport, 0) > 0.0
             end)
    end
  end

  describe "passenger considerations" do
    test "passenger_opportunity is 0 with no passenger contracts" do
      state = %{
        passenger_capacity: 20,
        available_contracts: [
          %{
            contract_type: "delivery",
            source_location: "a",
            passenger_count: 0,
            payment: 1000,
            distance: 50
          }
        ]
      }

      {value, :profit} = Considerations.passenger_opportunity(state)
      assert value == 0.0
    end

    test "passenger_opportunity is 0 for ships with no passenger capacity" do
      state = %{
        passenger_capacity: 0,
        available_contracts: [passenger_contract(payment: 2000, count: 10, dist: 50)]
      }

      {value, :profit} = Considerations.passenger_opportunity(state)
      assert value == 0.0
    end

    test "passenger_opportunity scales with payment-per-tick" do
      low =
        %{
          passenger_capacity: 20,
          available_contracts: [passenger_contract(payment: 500, count: 10, dist: 100)]
        }

      high =
        %{
          passenger_capacity: 20,
          available_contracts: [passenger_contract(payment: 5000, count: 10, dist: 100)]
        }

      {low_v, :profit} = Considerations.passenger_opportunity(low)
      {high_v, :profit} = Considerations.passenger_opportunity(high)

      assert high_v > low_v
    end

    test "passenger_capacity_remaining reports free seats as a fraction" do
      empty = %{passenger_capacity: 20, passengers: 0}
      full = %{passenger_capacity: 20, passengers: 20}
      half = %{passenger_capacity: 20, passengers: 10}

      {empty_v, :profit} = Considerations.passenger_capacity_remaining(empty)
      {full_v, :profit} = Considerations.passenger_capacity_remaining(full)
      assert empty_v == 1.0
      assert full_v == 0.0
      {half_v, :profit} = Considerations.passenger_capacity_remaining(half)
      assert_in_delta half_v, 0.5, 0.001
    end
  end

  describe "goal selection" do
    test ":fulfill_passenger_transport is in available_actions" do
      actions = Goals.available_actions()
      assert Enum.any?(actions, fn {name, _} -> name == :fulfill_passenger_transport end)
    end

    test "courier ship with a passenger contract scores passenger goal high" do
      state = %{
        passenger_capacity: 20,
        passengers: 0,
        available_contracts: [passenger_contract(payment: 3000, count: 15, dist: 80)],
        faction_id: "independent",
        crew: %{morale: 70},
        cargo: %{},
        cargo_capacity: 50,
        fuel: 60.0,
        fuel_capacity: 80.0,
        credits: 4000,
        fuel_consumption_rate: 0.03,
        memory: %{known_prices: %{}, visited: []}
      }

      considerations = Goals.evaluate_considerations(state)

      scored =
        Utility.rank_actions(Goals.available_actions(), considerations, Personality.courier())

      # Passenger goal should be in the top 2 for a courier with an
      # available passenger run (prefer_goals bonus plus passenger
      # opportunity score).
      top_two = scored |> Enum.take(2) |> Enum.map(&elem(&1, 0))
      assert :fulfill_passenger_transport in top_two
    end
  end

  defp passenger_contract(opts) do
    %{
      contract_type: "passenger_transport",
      source_location: "source",
      destination_location: "dest",
      passenger_count: Keyword.get(opts, :count, 10),
      quantity: Keyword.get(opts, :count, 10),
      payment: Keyword.get(opts, :payment, 1000),
      distance: Keyword.get(opts, :dist, 100),
      faction_id: Keyword.get(opts, :faction_id, "independent")
    }
  end
end
