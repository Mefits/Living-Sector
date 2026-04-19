defmodule Simulator.Economy.ContractBoardTest do
  use ExUnit.Case

  alias Simulator.Economy.ContractBoard

  setup do
    ContractBoard.reset()
    :ok
  end

  defp post_food_contract(opts \\ %{}) do
    ContractBoard.post_contract(
      Map.merge(
        %{
          contract_type: "delivery",
          requestor_type: "facility",
          requestor_id: "facility-belt-outpost",
          commodity: "food",
          quantity: 500,
          destination_location: "belt-outpost",
          payment: 15_000,
          posted_at_tick: 100,
          deadline_tick: 300
        },
        opts
      )
    )
  end

  describe "post_contract/1" do
    test "creates and stores a contract" do
      {:ok, contract} = post_food_contract()

      assert contract.id =~ "contract-"
      assert contract.status == "posted"
      assert contract.quantity_remaining == 500
    end

    test "enforces max contracts per requestor" do
      # Max is 5 per requestor
      for _ <- 1..5, do: post_food_contract()
      assert {:error, :too_many_contracts} = post_food_contract()
    end
  end

  describe "query_contracts/1" do
    test "returns posted contracts" do
      post_food_contract()
      contracts = ContractBoard.query_contracts()
      assert length(contracts) == 1
    end

    test "filters by destination" do
      post_food_contract()

      post_food_contract(%{
        requestor_id: "facility-earth-station",
        destination_location: "earth-station"
      })

      belt = ContractBoard.query_contracts(destination: "belt-outpost")
      assert length(belt) == 1

      earth = ContractBoard.query_contracts(destination: "earth-station")
      assert length(earth) == 1
    end

    test "filters by commodity" do
      post_food_contract()

      post_food_contract(%{
        requestor_id: "facility-mars-station",
        commodity: "fuel",
        destination_location: "mars-station"
      })

      food = ContractBoard.query_contracts(commodity: "food")
      assert length(food) == 1

      fuel = ContractBoard.query_contracts(commodity: "fuel")
      assert length(fuel) == 1
    end

    test "sorts by payment descending" do
      post_food_contract(%{payment: 5_000, requestor_id: "req-1"})
      post_food_contract(%{payment: 20_000, requestor_id: "req-2"})

      [first, second] = ContractBoard.query_contracts()
      assert first.payment > second.payment
    end
  end

  describe "accept_contract/3" do
    test "moves contract to accepted" do
      {:ok, contract} = post_food_contract()
      {:ok, accepted} = ContractBoard.accept_contract(contract.id, "ship-artemis-7", 110)

      assert accepted.status == "accepted"
      assert accepted.fulfiller_id == "ship-artemis-7"
    end

    test "returns error for non-existent contract" do
      assert {:error, :not_found} = ContractBoard.accept_contract("nope", "ship-1", 100)
    end
  end

  describe "full lifecycle (legacy)" do
    test "post → accept → work → deliver → pay" do
      {:ok, contract} = post_food_contract()
      {:ok, _} = ContractBoard.accept_contract(contract.id, "ship-1", 110)
      {:ok, _} = ContractBoard.begin_work(contract.id)
      {:ok, _} = ContractBoard.deliver(contract.id, 500)
      {:ok, completed, payout} = ContractBoard.release_payment(contract.id, 200)

      assert completed.status == "completed"
      assert payout == 15_000
    end

    test "partial delivery keeps contract in_progress" do
      {:ok, contract} = post_food_contract()
      {:ok, _} = ContractBoard.accept_contract(contract.id, "ship-1", 110)
      {:ok, _} = ContractBoard.begin_work(contract.id)
      {:ok, partial} = ContractBoard.deliver(contract.id, 200)

      assert partial.status == "in_progress"
      assert partial.quantity_remaining == 300
    end
  end

  # --- Delivery Contract Tests ---

  defp post_delivery_contract(opts \\ %{}) do
    ContractBoard.post_contract(
      Map.merge(
        %{
          contract_type: "delivery",
          requestor_type: "facility",
          requestor_id: "facility-earth-station",
          commodity: "ore",
          quantity: 200,
          source_location: "belt-outpost",
          destination_location: "earth-station",
          payment: 7_000,
          delivery_fee: 2_000,
          cargo_deposit: 5_000,
          cargo_value: 5_000,
          reserve_id: "reserve-market-belt-1",
          posted_at_tick: 100,
          deadline_tick: 400
        },
        opts
      )
    )
  end

  describe "delivery contract lifecycle" do
    test "post → accept → pickup → transit → deliver" do
      {:ok, contract} = post_delivery_contract()
      {:ok, _} = ContractBoard.accept_contract(contract.id, "ship-1", 110)
      {:ok, picked_up} = ContractBoard.pickup_cargo(contract.id, "ship-1", 120)

      assert picked_up.status == "picked_up"
      assert picked_up.picked_up_at_tick == 120

      {:ok, _} = ContractBoard.begin_transit(contract.id)
      {:ok, completed, payout} = ContractBoard.confirm_delivery(contract.id, 200)

      assert completed.status == "completed"
      assert payout == 7_000
    end

    test "pickup rejects wrong fulfiller" do
      {:ok, contract} = post_delivery_contract()
      {:ok, _} = ContractBoard.accept_contract(contract.id, "ship-1", 110)

      assert {:error, :wrong_fulfiller} =
               ContractBoard.pickup_cargo(contract.id, "ship-other", 120)
    end
  end

  describe "delivery contract queries" do
    test "finds delivery contracts by source location" do
      post_delivery_contract(%{source_location: "belt-outpost", requestor_id: "req-1"})
      post_delivery_contract(%{source_location: "mars-station", requestor_id: "req-2"})

      belt = ContractBoard.query_contracts(source: "belt-outpost")
      assert length(belt) >= 1
      assert Enum.all?(belt, &(&1.source_location == "belt-outpost"))
    end
  end
end
