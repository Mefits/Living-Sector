defmodule Simulator.Agents.FactionAgentRebuildTest do
  use Simulator.SimulationCase, async: false

  alias Simulator.Agents.FactionAgent
  alias Simulator.Economy.ContractBoard

  defp start_faction(overrides \\ %{}) do
    config =
      Map.merge(
        %{
          id: "faction-terran-authority",
          faction_id: "terran-authority",
          name: "Terran Authority",
          treasury: 100_000,
          member_facilities: []
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(Simulator.AgentSupervisor, {FactionAgent, config})

    pid
  end

  defp post_subsidy(faction_id, opts \\ %{}) do
    ContractBoard.post_contract(
      Map.merge(
        %{
          contract_type: "supply",
          requestor_type: "faction",
          requestor_id: faction_id,
          faction_id: faction_id,
          commodity: "fuel",
          quantity: 200,
          quantity_remaining: 200,
          destination_location: "earth-station",
          payment: 2_500,
          posted_at_tick: 50,
          deadline_tick: 500
        },
        opts
      )
    )
  end

  describe "active_subsidies rebuild on init" do
    test "starts empty when no outstanding subsidies exist" do
      pid = start_faction()
      state = FactionAgent.get_state(pid)
      assert MapSet.size(state.active_subsidies) == 0
    end

    test "populates from ContractBoard for the matching faction" do
      {:ok, c1} = post_subsidy("terran-authority")
      {:ok, c2} = post_subsidy("terran-authority", %{destination_location: "mars-station"})
      {:ok, _other} = post_subsidy("frontier-ventures")

      pid = start_faction()
      state = FactionAgent.get_state(pid)

      assert MapSet.size(state.active_subsidies) == 2
      assert MapSet.member?(state.active_subsidies, c1.id)
      assert MapSet.member?(state.active_subsidies, c2.id)
    end

    test "skips completed / expired / cancelled contracts" do
      {:ok, live} = post_subsidy("terran-authority")
      {:ok, finished} = post_subsidy("terran-authority", %{destination_location: "luna-base"})

      # Flip the finished one into a terminal status directly in ETS so
      # the rebuild path has a realistic "old settled subsidy" to skip.
      [{_, contract}] = :ets.lookup(:contract_board, finished.id)
      :ets.insert(:contract_board, {finished.id, %{contract | status: "completed"}})

      pid = start_faction()
      state = FactionAgent.get_state(pid)

      assert MapSet.member?(state.active_subsidies, live.id)
      refute MapSet.member?(state.active_subsidies, finished.id)
    end

    test "handles empty faction_id requestor gracefully" do
      # An orphan contract (no faction) shouldn't leak into the MapSet.
      {:ok, _} =
        ContractBoard.post_contract(%{
          contract_type: "delivery",
          requestor_type: "facility",
          requestor_id: "facility-somewhere",
          commodity: "food",
          quantity: 100,
          quantity_remaining: 100,
          destination_location: "somewhere",
          payment: 500,
          posted_at_tick: 1,
          deadline_tick: 100
        })

      pid = start_faction()
      state = FactionAgent.get_state(pid)

      assert MapSet.size(state.active_subsidies) == 0
    end
  end
end
