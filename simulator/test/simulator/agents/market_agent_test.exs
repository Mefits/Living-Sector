defmodule Simulator.Agents.MarketAgentTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.MarketAgent

  defp start_market(overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: "market-earth",
          facility_id: "earth-station",
          prices: %{ore: 40.0, fuel: 25.0, food: 15.0},
          supply: %{ore: 500, fuel: 500, food: 500},
          demand: %{ore: 20, fuel: 50, food: 100},
          production: %{ore: 0, fuel: 30, food: 80},
          consumption: %{ore: 0, fuel: 0, food: 0},
          price_elasticity: 0.05,
          spread: 0.10
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Simulator.AgentSupervisor,
        {MarketAgent, config}
      )

    pid
  end

  defp send_tick(pid, tick) do
    send(pid, {:tick, tick})
    :sys.get_state(pid)
  end

  describe "query_prices/1" do
    test "returns current commodity prices" do
      pid = start_market()
      prices = MarketAgent.query_prices(pid)

      assert prices.ore == 40.0
      assert prices.fuel == 25.0
      assert prices.food == 15.0
    end
  end

  describe "place_buy_order/2 and place_sell_order/2" do
    test "accepts buy orders" do
      pid = start_market()

      {:ok, order_id} =
        MarketAgent.place_buy_order(pid, %{
          agent_id: "ship-1",
          commodity: :ore,
          quantity: 100,
          price: 45.0
        })

      assert is_integer(order_id)

      state = MarketAgent.get_state(pid)
      assert length(state.pending_buy_orders) == 1
    end

    test "accepts sell orders" do
      pid = start_market()

      {:ok, _order_id} =
        MarketAgent.place_sell_order(pid, %{
          agent_id: "miner-1",
          commodity: :ore,
          quantity: 50,
          price: 35.0
        })

      state = MarketAgent.get_state(pid)
      assert length(state.pending_sell_orders) == 1
    end
  end

  @prod_cons_interval 5 * Simulator.Simulation.Config.tick_multiplier()

  describe "tick cycle" do
    test "production adds to supply on interval" do
      pid = start_market(%{production: %{ore: 0, fuel: 30, food: 80}})

      state = send_tick(pid, @prod_cons_interval)

      # fuel started at 500, production adds 30
      assert state.supply.fuel == 530
      # food started at 500, production adds 80
      assert state.supply.food == 580
    end

    test "consumption subtracts from supply on interval" do
      pid =
        start_market(%{
          production: %{ore: 0, fuel: 0, food: 0},
          consumption: %{ore: 10, fuel: 20, food: 50}
        })

      state = send_tick(pid, @prod_cons_interval)

      assert state.supply.ore == 490
      assert state.supply.fuel == 480
      assert state.supply.food == 450
    end

    test "prices respond to supply/demand imbalance" do
      # High demand, low supply for food
      pid =
        start_market(%{
          supply: %{ore: 500, fuel: 500, food: 50},
          demand: %{ore: 20, fuel: 50, food: 200}
        })

      state = send_tick(pid, 1)

      # Food price should increase (demand >> supply)
      assert state.prices.food > 15.0
    end

    test "orders are matched during tick" do
      pid = start_market()

      Simulator.Events.subscribe("market:earth-station")

      MarketAgent.place_buy_order(pid, %{
        agent_id: "ship-1",
        commodity: :ore,
        quantity: 100,
        price: 50.0
      })

      MarketAgent.place_sell_order(pid, %{
        agent_id: "miner-1",
        commodity: :ore,
        quantity: 100,
        price: 35.0
      })

      state = send_tick(pid, 1)

      # Orders should be matched and cleared
      assert state.pending_buy_orders == []
      assert state.pending_sell_orders == []

      # Trade executed event should be broadcast
      assert_receive {:trade_executed, %{commodity: :ore, quantity: 100}}
    end

    test "price updates are broadcast each tick" do
      pid = start_market()
      Simulator.Events.subscribe("market:earth-station")

      send_tick(pid, 1)

      assert_receive {:price_update,
                      %{
                        facility_id: "earth-station",
                        prices: %{ore: _, fuel: _, food: _},
                        tick: 1
                      }}
    end

    test "price history is recorded" do
      pid = start_market()

      send_tick(pid, 1)
      send_tick(pid, 2)
      state = send_tick(pid, 3)

      # Should have 3 entries in history for each commodity
      assert length(state.price_history.ore) == 3
      assert length(state.price_history.fuel) == 3
    end

    test "expired orders are removed" do
      pid = start_market()

      # Place an order that will be "old"
      MarketAgent.place_buy_order(pid, %{
        agent_id: "ship-1",
        commodity: :ore,
        quantity: 100,
        price: 1.0
      })

      # Advance well past expiry (distance-based, scaled by tick_multiplier)
      state = send_tick(pid, 50_000)

      assert state.pending_buy_orders == []
    end
  end

  describe "supply floor" do
    test "supply cannot go below zero from consumption" do
      pid =
        start_market(%{
          supply: %{ore: 5, fuel: 5, food: 5},
          consumption: %{ore: 100, fuel: 100, food: 100}
        })

      state = send_tick(pid, @prod_cons_interval)

      assert state.supply.ore == 0
      assert state.supply.fuel == 0
      assert state.supply.food == 0
    end
  end

  describe "dynamic demand" do
    test "consumption from pop feed inflates rolling demand" do
      pid =
        start_market(%{
          supply: %{ore: 500, fuel: 500, food: 500},
          demand: %{ore: 0, fuel: 0, food: 0},
          consumption: %{ore: 0, fuel: 0, food: 25}
        })

      # Run several consumption intervals so the window accumulates.
      for t <- 1..(@prod_cons_interval * 3) do
        send_tick(pid, t)
      end

      state = MarketAgent.get_state(pid)
      assert state.demand.food > 0
    end

    test "bump_demand/3 adds pressure without moving supply" do
      pid =
        start_market(%{
          supply: %{ore: 500, fuel: 500, food: 500},
          demand: %{ore: 0, fuel: 0, food: 0},
          consumption: %{ore: 0, fuel: 0, food: 0}
        })

      MarketAgent.bump_demand(pid, :ore, 50)
      send_tick(pid, 1)

      state = MarketAgent.get_state(pid)
      # Supply unchanged; demand reflects the bump.
      assert state.supply.ore == 500
      assert state.demand.ore > 0
    end

    test "shortage_ticks counter increments under sustained scarcity" do
      pid =
        start_market(%{
          supply: %{ore: 5, fuel: 5, food: 5},
          demand: %{ore: 100, fuel: 100, food: 100}
        })

      # Drive several ticks with no restock.
      for t <- 1..10 do
        send_tick(pid, t)
      end

      state = MarketAgent.get_state(pid)
      assert Map.get(state.shortage_ticks, :ore, 0) > 0
    end

    test "shortage_ticks resets when supply recovers" do
      pid =
        start_market(%{
          supply: %{ore: 0, fuel: 500, food: 500},
          demand: %{ore: 100, fuel: 50, food: 100}
        })

      # Accumulate some shortage.
      for t <- 1..5 do
        send_tick(pid, t)
      end

      # Restock and tick again.
      MarketAgent.add_supply(pid, %{ore: 10_000})
      send_tick(pid, 6)

      state = MarketAgent.get_state(pid)
      assert Map.get(state.shortage_ticks, :ore, 0) == 0
    end
  end

  describe "reserve_goods/2" do
    test "reserves goods from supply" do
      pid = start_market(%{supply: %{ore: 500, fuel: 500, food: 500}})

      {:ok, reserve_id} =
        MarketAgent.reserve_goods(pid, %{
          commodity: :ore,
          quantity: 100,
          owner_id: "facility-earth-station",
          tick: 0
        })

      assert is_binary(reserve_id)

      state = MarketAgent.get_state(pid)
      assert state.supply.ore == 400
      assert map_size(state.reserved_goods) == 1

      reserve = state.reserved_goods[reserve_id]
      assert reserve.commodity == :ore
      assert reserve.quantity == 100
      assert reserve.owner_id == "facility-earth-station"
    end

    test "fails when supply is insufficient" do
      pid = start_market(%{supply: %{ore: 50, fuel: 500, food: 500}})

      assert {:error, :insufficient_supply} =
               MarketAgent.reserve_goods(pid, %{
                 commodity: :ore,
                 quantity: 100,
                 owner_id: "facility-x",
                 tick: 0
               })

      state = MarketAgent.get_state(pid)
      assert state.supply.ore == 50
      assert state.reserved_goods == %{}
    end

    test "multiple reserves track independently" do
      pid = start_market(%{supply: %{ore: 500, fuel: 500, food: 500}})

      {:ok, r1} =
        MarketAgent.reserve_goods(pid, %{commodity: :ore, quantity: 100, owner_id: "f-1", tick: 0})

      {:ok, r2} =
        MarketAgent.reserve_goods(pid, %{
          commodity: :fuel,
          quantity: 200,
          owner_id: "f-2",
          tick: 0
        })

      assert r1 != r2

      state = MarketAgent.get_state(pid)
      assert state.supply.ore == 400
      assert state.supply.fuel == 300
      assert map_size(state.reserved_goods) == 2
    end
  end

  describe "pickup_reserved/3" do
    test "removes reservation and returns goods info" do
      pid = start_market(%{supply: %{ore: 500, fuel: 500, food: 500}})

      {:ok, reserve_id} =
        MarketAgent.reserve_goods(pid, %{commodity: :ore, quantity: 100, owner_id: "f-1", tick: 0})

      {:ok, commodity, quantity} = MarketAgent.pickup_reserved(pid, reserve_id, "ship-1")
      assert commodity == :ore
      assert quantity == 100

      state = MarketAgent.get_state(pid)
      assert state.reserved_goods == %{}
      # Supply stays at 400 — goods went to the ship, not back to supply
      assert state.supply.ore == 400
    end

    test "fails for nonexistent reservation" do
      pid = start_market()
      assert {:error, :not_found} = MarketAgent.pickup_reserved(pid, "bad-id", "ship-1")
    end
  end

  describe "release_reserved/2" do
    test "returns goods to supply" do
      pid = start_market(%{supply: %{ore: 500, fuel: 500, food: 500}})

      {:ok, reserve_id} =
        MarketAgent.reserve_goods(pid, %{commodity: :ore, quantity: 100, owner_id: "f-1", tick: 0})

      assert :ok = MarketAgent.release_reserved(pid, reserve_id)

      state = MarketAgent.get_state(pid)
      assert state.supply.ore == 500
      assert state.reserved_goods == %{}
    end
  end

  describe "query_reserved/2" do
    test "returns reserves for a specific owner" do
      pid = start_market(%{supply: %{ore: 500, fuel: 500, food: 500}})

      MarketAgent.reserve_goods(pid, %{commodity: :ore, quantity: 100, owner_id: "f-1", tick: 0})
      MarketAgent.reserve_goods(pid, %{commodity: :fuel, quantity: 50, owner_id: "f-2", tick: 0})

      reserves = MarketAgent.query_reserved(pid, "f-1")
      assert length(reserves) == 1
      assert hd(reserves).commodity == :ore
    end
  end

  describe "reserve expiry" do
    test "expired reserves return goods to supply" do
      pid = start_market(%{supply: %{ore: 500, fuel: 500, food: 500}})

      {:ok, _reserve_id} =
        MarketAgent.reserve_goods(pid, %{commodity: :ore, quantity: 100, owner_id: "f-1", tick: 0})

      state = MarketAgent.get_state(pid)
      assert state.supply.ore == 400

      # Tick well past the reserve expiry (200 * tick_multiplier)
      Simulator.Events.subscribe("market:earth-station")
      state = send_tick(pid, 50_000)

      assert state.supply.ore == 500
      assert state.reserved_goods == %{}
      assert_receive {:reserve_expired, %{owner_id: "f-1", commodity: :ore}}
    end

    test "non-expired reserves are kept" do
      pid = start_market(%{supply: %{ore: 500, fuel: 500, food: 500}})

      {:ok, _reserve_id} =
        MarketAgent.reserve_goods(pid, %{commodity: :ore, quantity: 100, owner_id: "f-1", tick: 0})

      state = send_tick(pid, 100)

      assert state.supply.ore == 400
      assert map_size(state.reserved_goods) == 1
    end
  end
end
