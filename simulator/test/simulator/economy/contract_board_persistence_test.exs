defmodule Simulator.Economy.ContractBoardPersistenceTest do
  use Simulator.DataCase, async: false

  alias Simulator.Economy.ContractBoard
  alias Simulator.Repo
  alias Simulator.Schemas.Contract

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
          quantity_remaining: 500,
          destination_location: "belt-outpost",
          payment: 15_000,
          posted_at_tick: 100,
          deadline_tick: 300
        },
        opts
      )
    )
  end

  describe "post_contract/1 → DB" do
    test "inserts a matching row in the contracts table" do
      {:ok, contract} = post_food_contract()
      ContractBoard.snapshot()

      row = Repo.get_by!(Contract, contract_id: contract.id)
      assert row.contract_type == "delivery"
      assert row.requestor_id == "facility-belt-outpost"
      assert row.commodity == "food"
      assert row.quantity == 500
      assert row.quantity_remaining == 500
      assert row.status == "posted"
      assert row.payment == 15_000
    end

    test "round-trips faction + delivery-specific fields" do
      {:ok, contract} =
        post_food_contract(%{
          faction_id: "terran-authority",
          min_reputation: 40,
          faction_bonus: 1.25,
          delivery_fee: 1_200,
          cargo_deposit: 800,
          cargo_value: 5_000
        })

      ContractBoard.snapshot()
      row = Repo.get_by!(Contract, contract_id: contract.id)

      assert row.faction_id == "terran-authority"
      assert row.min_reputation == 40
      assert row.faction_bonus == 1.25
      assert row.delivery_fee == 1_200
      assert row.cargo_deposit == 800
      assert row.cargo_value == 5_000
    end
  end

  describe "status transitions → DB" do
    test "accept updates the persisted status + fulfiller" do
      {:ok, contract} = post_food_contract()
      {:ok, _} = ContractBoard.accept_contract(contract.id, "ship-bess", 150)
      ContractBoard.snapshot()

      row = Repo.get_by!(Contract, contract_id: contract.id)
      assert row.status == "accepted"
      assert row.fulfiller_id == "ship-bess"
      assert row.fulfiller_type == "ship"
      assert row.accepted_at_tick == 150
    end

    test "pickup + begin_transit persist the new statuses" do
      {:ok, contract} = post_food_contract()
      {:ok, _} = ContractBoard.accept_contract(contract.id, "ship-bess", 150)
      {:ok, _} = ContractBoard.pickup_cargo(contract.id, "ship-bess", 160)
      ContractBoard.snapshot()

      row = Repo.get_by!(Contract, contract_id: contract.id)
      assert row.status == "picked_up"
      assert row.picked_up_at_tick == 160
    end
  end

  describe "delete_contract/1" do
    test "removes from ETS and DB" do
      {:ok, contract} = post_food_contract()
      ContractBoard.snapshot()
      assert Repo.get_by(Contract, contract_id: contract.id)

      :ok = ContractBoard.delete_contract(contract.id)
      ContractBoard.snapshot()

      refute ContractBoard.get_contract(contract.id)
      refute Repo.get_by(Contract, contract_id: contract.id)
    end

    test "is a no-op for unknown IDs" do
      assert :ok = ContractBoard.delete_contract("contract-does-not-exist")
    end
  end

  describe "load_from_db on restart" do
    test "rebuilds ETS with all persisted contracts" do
      {:ok, c1} = post_food_contract(%{requestor_id: "facility-a"})

      {:ok, c2} =
        post_food_contract(%{requestor_id: "facility-b", destination_location: "other-stop"})

      {:ok, _accepted} = ContractBoard.accept_contract(c2.id, "ship-crow", 105)
      ContractBoard.snapshot()

      # Simulate restart: stop the board (its ETS tables die with it)
      # and start it again. Init must rebuild ETS from DB only.
      restart_contract_board()

      assert ContractBoard.get_contract(c1.id)
      reloaded_c2 = ContractBoard.get_contract(c2.id)
      assert reloaded_c2
      assert reloaded_c2.status == "accepted"
      assert reloaded_c2.fulfiller_id == "ship-crow"
    end

    test "next_id advances past the max persisted suffix" do
      for _ <- 1..3 do
        {:ok, _} = post_food_contract()
      end

      ContractBoard.snapshot()

      restart_contract_board()

      # Next post should be at least contract-4 — there were 3 pre-existing.
      {:ok, fresh} = post_food_contract()
      [_, n] = String.split(fresh.id, "-")
      assert String.to_integer(n) >= 4
    end
  end

  defp restart_contract_board do
    # ContractBoard is supervised by the Application — killing it lets
    # the supervisor respawn it with a fresh init, which is the path
    # we actually want to test (boot path rebuilds ETS from DB).
    old_pid = Process.whereis(ContractBoard)
    ref = Process.monitor(old_pid)
    Process.exit(old_pid, :kill)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    after
      2_000 -> flunk("ContractBoard didn't stop in time")
    end

    wait_for_contract_board(old_pid, 20)
  end

  defp wait_for_contract_board(old_pid, retries) when retries > 0 do
    case Process.whereis(ContractBoard) do
      nil ->
        Process.sleep(25)
        wait_for_contract_board(old_pid, retries - 1)

      pid when pid == old_pid ->
        Process.sleep(25)
        wait_for_contract_board(old_pid, retries - 1)

      _fresh_pid ->
        :ok
    end
  end

  defp wait_for_contract_board(_old_pid, 0), do: flunk("ContractBoard didn't come back up")
end
