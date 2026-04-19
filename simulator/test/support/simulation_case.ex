defmodule Simulator.SimulationCase do
  @moduledoc """
  Test case template for simulation tests.

  Uses the application-level `Simulator.AgentRegistry` and
  `Simulator.AgentSupervisor` (started by `Simulator.Application`).
  Terminates all agent children after each test to prevent leaks.

  ## Usage

      use Simulator.SimulationCase
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Simulator.SimulationCase
    end
  end

  setup do
    # Ensure the TickCoordinator is stopped/reset between tests
    if Process.whereis(Simulator.TickCoordinator) do
      try do
        Simulator.TickCoordinator.stop()
      catch
        :exit, _ -> :ok
      end
    end

    # Clear the ContractBoard between tests so posted contracts
    # don't leak into later tests' active_subsidies rebuilds.
    if Process.whereis(Simulator.Economy.ContractBoard) do
      try do
        Simulator.Economy.ContractBoard.reset()
      catch
        :exit, _ -> :ok
      end
    end

    # Wipe agent snapshot ETS so tests don't see stale rows from
    # earlier tests that spawned agents with the same ids.
    Simulator.AgentSnapshots.reset()

    on_exit(fn ->
      # Terminate all dynamically-started agents after each test
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Simulator.AgentSupervisor) do
        DynamicSupervisor.terminate_child(Simulator.AgentSupervisor, pid)
      end

      # Stop the tick coordinator if running
      if Process.whereis(Simulator.TickCoordinator) do
        try do
          Simulator.TickCoordinator.stop()
        catch
          :exit, _ -> :ok
        end
      end
    end)

    :ok
  end
end
