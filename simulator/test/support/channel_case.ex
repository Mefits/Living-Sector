defmodule SimulatorWeb.ChannelCase do
  @moduledoc """
  Test case for Phoenix Channel tests.

  Imports `Phoenix.ChannelTest` for `socket/0`, `subscribe_and_join/3`,
  `push/3`, `assert_push`, `assert_reply`, etc.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest

      @endpoint SimulatorWeb.Endpoint
    end
  end

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Simulator.AgentSupervisor) do
        DynamicSupervisor.terminate_child(Simulator.AgentSupervisor, pid)
      end

      try do
        Simulator.TickCoordinator.stop()
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end
end
