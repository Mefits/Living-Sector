defmodule Simulator.Economy.ContractLifecycleTest do
  use ExUnit.Case, async: true

  alias Simulator.Economy.ContractLifecycle

  defp sample_contract do
    {:ok, contract} =
      ContractLifecycle.post(%{
        contract_type: "delivery",
        requestor_type: "facility",
        requestor_id: "facility-belt-outpost",
        commodity: "food",
        quantity: 500,
        destination_location: "belt-outpost",
        payment: 15_000,
        posted_at_tick: 100,
        deadline_tick: 300
      })

    contract
  end

  describe "post/1" do
    test "creates a contract in posted status" do
      contract = sample_contract()
      assert contract.status == "posted"
      assert contract.quantity_remaining == 500
      assert contract.escrow_amount == 15_000
    end
  end

  describe "accept/3" do
    test "moves from posted to accepted" do
      contract = sample_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-artemis-7", 110)

      assert accepted.status == "accepted"
      assert accepted.fulfiller_id == "ship-artemis-7"
      assert accepted.accepted_at_tick == 110
    end

    test "rejects invalid status" do
      contract = %{sample_contract() | status: "completed"}
      assert {:error, :invalid_status} = ContractLifecycle.accept(contract, "ship-1", 110)
    end
  end

  describe "begin_work/1" do
    test "moves from accepted to in_progress" do
      contract = sample_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, working} = ContractLifecycle.begin_work(accepted)

      assert working.status == "in_progress"
    end
  end

  describe "fulfill/2" do
    test "full delivery completes the contract" do
      contract = sample_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, working} = ContractLifecycle.begin_work(accepted)
      {:ok, fulfilled} = ContractLifecycle.fulfill(working, 500)

      assert fulfilled.status == "fulfilled"
      assert fulfilled.quantity_remaining == 0
    end

    test "partial delivery keeps contract in_progress" do
      contract = sample_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, working} = ContractLifecycle.begin_work(accepted)
      {:ok, partial} = ContractLifecycle.fulfill(working, 200)

      assert partial.status == "in_progress"
      assert partial.quantity_remaining == 300
    end
  end

  describe "pay/1" do
    test "releases escrow" do
      contract = sample_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, working} = ContractLifecycle.begin_work(accepted)
      {:ok, fulfilled} = ContractLifecycle.fulfill(working, 500)
      {:ok, paid, payout} = ContractLifecycle.pay(fulfilled)

      assert paid.status == "paid"
      assert paid.escrow_amount == 0
      assert payout == 15_000
    end
  end

  describe "complete/2" do
    test "finalizes the contract" do
      contract = sample_contract()
      {:ok, a} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, w} = ContractLifecycle.begin_work(a)
      {:ok, f} = ContractLifecycle.fulfill(w, 500)
      {:ok, p, _} = ContractLifecycle.pay(f)
      {:ok, completed} = ContractLifecycle.complete(p, 200)

      assert completed.status == "completed"
      assert completed.completed_at_tick == 200
    end
  end

  describe "expire/1" do
    test "returns escrow refund" do
      contract = sample_contract()
      {:ok, expired, refund} = ContractLifecycle.expire(contract)

      assert expired.status == "expired"
      assert refund == 15_000
    end
  end

  describe "cancel/1" do
    test "cancels a posted contract and refunds escrow" do
      contract = sample_contract()
      {:ok, cancelled, refund} = ContractLifecycle.cancel(contract)

      assert cancelled.status == "cancelled"
      assert refund == 15_000
    end

    test "cannot cancel an accepted contract" do
      contract = sample_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      assert {:error, :invalid_status} = ContractLifecycle.cancel(accepted)
    end
  end

  describe "escalate/1" do
    test "increases payment for posted contracts" do
      contract = %{sample_contract() | urgency: 0.5}
      escalated = ContractLifecycle.escalate(contract)

      assert escalated.payment > contract.payment
      assert escalated.escrow_amount > contract.escrow_amount
    end

    test "does not escalate non-posted contracts" do
      contract = %{sample_contract() | status: "accepted"}
      assert ContractLifecycle.escalate(contract) == contract
    end
  end

  # --- Delivery Contract Transitions ---

  defp delivery_contract do
    {:ok, contract} =
      ContractLifecycle.post(%{
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
        reserve_id: "reserve-market-belt-outpost-1",
        posted_at_tick: 100,
        deadline_tick: 400
      })

    contract
  end

  describe "pickup/2" do
    test "moves accepted to picked_up" do
      contract = delivery_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, picked_up} = ContractLifecycle.pickup(accepted, 120)

      assert picked_up.status == "picked_up"
      assert picked_up.picked_up_at_tick == 120
    end

    test "rejects non-accepted status" do
      contract = delivery_contract()
      assert {:error, :invalid_status} = ContractLifecycle.pickup(contract, 120)
    end
  end

  describe "begin_transit/1" do
    test "moves picked_up to in_transit" do
      contract = delivery_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, picked_up} = ContractLifecycle.pickup(accepted, 120)
      {:ok, in_transit} = ContractLifecycle.begin_transit(picked_up)

      assert in_transit.status == "in_transit"
    end
  end

  describe "confirm_delivery/2" do
    test "delivers and returns payout (delivery_fee + cargo_deposit)" do
      contract = delivery_contract()
      {:ok, a} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, p} = ContractLifecycle.pickup(a, 120)
      {:ok, t} = ContractLifecycle.begin_transit(p)
      {:ok, delivered, payout} = ContractLifecycle.confirm_delivery(t, 200)

      assert delivered.status == "delivered"
      assert delivered.delivered_at_tick == 200
      assert payout == 7_000
    end

    test "rejects non in_transit status" do
      contract = delivery_contract()
      {:ok, accepted} = ContractLifecycle.accept(contract, "ship-1", 110)
      assert {:error, :invalid_status} = ContractLifecycle.confirm_delivery(accepted, 200)
    end
  end

  describe "complete_delivery/2" do
    test "completes a delivered contract" do
      contract = delivery_contract()
      {:ok, a} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, p} = ContractLifecycle.pickup(a, 120)
      {:ok, t} = ContractLifecycle.begin_transit(p)
      {:ok, d, _} = ContractLifecycle.confirm_delivery(t, 200)
      {:ok, completed} = ContractLifecycle.complete_delivery(d, 200)

      assert completed.status == "completed"
      assert completed.completed_at_tick == 200
    end
  end

  describe "forfeit_deposit/1" do
    test "forfeits deposit from picked_up status" do
      contract = delivery_contract()
      {:ok, a} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, p} = ContractLifecycle.pickup(a, 120)
      {:ok, expired, forfeited} = ContractLifecycle.forfeit_deposit(p)

      assert expired.status == "expired"
      assert forfeited == 5_000
    end

    test "forfeits deposit from in_transit status" do
      contract = delivery_contract()
      {:ok, a} = ContractLifecycle.accept(contract, "ship-1", 110)
      {:ok, p} = ContractLifecycle.pickup(a, 120)
      {:ok, t} = ContractLifecycle.begin_transit(p)
      {:ok, expired, forfeited} = ContractLifecycle.forfeit_deposit(t)

      assert expired.status == "expired"
      assert forfeited == 5_000
    end

    test "rejects non-delivery statuses" do
      contract = delivery_contract()
      assert {:error, :invalid_status} = ContractLifecycle.forfeit_deposit(contract)
    end
  end
end
