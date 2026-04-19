defmodule SimulatorWeb.SimulationChannelTest do
  use SimulatorWeb.ChannelCase, async: false

  alias Simulator.Agents.MarketAgent

  setup do
    {:ok, _, socket} =
      socket(SimulatorWeb.UserSocket, "", %{})
      |> subscribe_and_join(SimulatorWeb.SimulationChannel, "simulation:tick")

    %{socket: socket}
  end

  describe "joining" do
    test "can join tick topic", %{socket: socket} do
      assert socket.assigns.topic == "tick"
    end

    test "can join market topic" do
      {:ok, _, socket} =
        socket(SimulatorWeb.UserSocket, "", %{})
        |> subscribe_and_join(SimulatorWeb.SimulationChannel, "simulation:market:earth-station")

      assert socket.assigns.topic == "market:earth-station"
    end

    test "can join ship topic" do
      {:ok, _, socket} =
        socket(SimulatorWeb.UserSocket, "", %{})
        |> subscribe_and_join(SimulatorWeb.SimulationChannel, "simulation:ship:ship-artemis-7")

      assert socket.assigns.topic == "ship:ship-artemis-7"
    end
  end

  describe "PubSub event relay" do
    test "relays PubSub events to the channel client" do
      Simulator.Events.broadcast("tick", :tick, %{tick: 42})

      assert_push "tick", %{"tick" => 42}
    end

    test "relays market events on market topic" do
      {:ok, _, _socket} =
        socket(SimulatorWeb.UserSocket, "", %{})
        |> subscribe_and_join(
          SimulatorWeb.SimulationChannel,
          "simulation:market:test-market"
        )

      Simulator.Events.broadcast("market:test-market", :price_update, %{
        ore: 42.0,
        fuel: 25.0
      })

      assert_push "price_update", %{"ore" => 42.0, "fuel" => 25.0}
    end
  end

  describe "get_state" do
    test "returns agent state when agent exists", %{socket: socket} do
      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Simulator.AgentSupervisor,
          {MarketAgent,
           %{
             id: "market-channel-test",
             facility_id: "channel-test",
             prices: %{ore: 40.0}
           }}
        )

      ref = push(socket, "get_state", %{"id" => "market-channel-test"})
      assert_reply ref, :ok, payload

      assert payload["prices"]["ore"] == 40.0
    end

    test "returns error for unknown agent", %{socket: socket} do
      ref = push(socket, "get_state", %{"id" => "nonexistent-agent"})
      assert_reply ref, :error, %{"reason" => "agent_not_found"}
    end
  end

  describe "get_snapshot" do
    test "returns snapshot of all markets", %{socket: socket} do
      {:ok, _pid} =
        DynamicSupervisor.start_child(
          Simulator.AgentSupervisor,
          {MarketAgent,
           %{
             id: "market-snapshot-test",
             facility_id: "snapshot-test",
             prices: %{ore: 55.0}
           }}
        )

      ref = push(socket, "get_snapshot", %{"type" => "markets"})
      assert_reply ref, :ok, %{"data" => data}

      assert is_list(data)
      assert Enum.any?(data, fn m -> m["prices"]["ore"] == 55.0 end)
    end
  end

  describe "sim_control" do
    test "can get tick status", %{socket: socket} do
      ref = push(socket, "sim_control", %{"action" => "get_tick"})
      assert_reply ref, :ok, %{"tick" => _, "running" => _}
    end

    test "can pause and resume", %{socket: socket} do
      Simulator.TickCoordinator.start()

      ref = push(socket, "sim_control", %{"action" => "pause"})
      assert_reply ref, :ok, %{"status" => "paused"}

      ref = push(socket, "sim_control", %{"action" => "resume"})
      assert_reply ref, :ok, %{"status" => "running"}
    end

    test "returns error for unknown action", %{socket: socket} do
      ref = push(socket, "sim_control", %{"action" => "explode"})
      assert_reply ref, :error, %{"reason" => "unknown_action"}
    end
  end
end
