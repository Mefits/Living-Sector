defmodule Simulator.ParentWatcher do
  @moduledoc """
  Watches the process that spawned this release and shuts the sim down
  when that parent dies.

  In the Godot desktop bundle, Godot launches the Elixir release as a
  subprocess. If the user force-quits Godot (or it crashes), we don't
  want an orphaned BEAM left behind holding the DB open.

  **Implementation: PID-alive poll every `@poll_interval_ms`.** Runs
  `kill -0 <parent_pid>`; a non-zero exit means the PID is gone →
  `System.stop(0)` → PersistenceManager flushes, SQLite WAL closes,
  release exits.

  The polling latency (~1s) is fine for a game shutdown.

  **Why not also watch stdin for EOF?** We used to. Opening a Port on
  fd=0 to detect EOF fights with BEAM's prim_tty driver, which by
  default tries to attach stdin as a shell. The "stealing control of
  fd=0" races wedged scheduler threads and cascaded into agent
  mailbox stalls. PID-poll alone is simpler and collision-free.

  The watcher is only started when the `PARENT_PID` environment
  variable is set — Godot passes it on spawn. Dev runs (`mix phx.server`)
  and manual `bin/simulator start` from a terminal don't set it, so
  this module is a no-op there.
  """

  use GenServer

  require Logger

  @poll_interval_ms 1_000

  @doc """
  Starts the watcher. Expects `:parent_pid` as a string (env-var format).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    parent_pid = Keyword.fetch!(opts, :parent_pid)

    schedule_poll()

    Logger.info(
      "ParentWatcher: watching parent PID #{parent_pid} (PID-poll every #{@poll_interval_ms}ms)"
    )

    {:ok, %{parent_pid: parent_pid}}
  end

  @impl true
  def handle_info(:poll, state) do
    if parent_alive?(state.parent_pid) do
      schedule_poll()
      {:noreply, state}
    else
      Logger.info("ParentWatcher: parent PID #{state.parent_pid} is gone — shutting down")
      shutdown()
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval_ms)

  # Does this PID still exist? POSIX uses `kill -0` (sends signal 0,
  # a no-op, reports whether delivery would have succeeded). Windows
  # has no signals — use `tasklist` with a PID filter and check
  # whether it finds the process. Both return exit 0 when alive.
  # On error we default to "alive" so transient issues don't cause a
  # false positive shutdown.
  defp parent_alive?(pid_string) when is_binary(pid_string) do
    case :os.type() do
      {:win32, _} ->
        case System.cmd(
               "tasklist",
               ["/FI", "PID eq " <> pid_string, "/NH", "/FO", "CSV"],
               stderr_to_stdout: true
             ) do
          # `tasklist` returns exit 0 whether or not the PID exists;
          # the signal is in the stdout text. A missing PID prints
          # "INFO: No tasks..." — anything else means a match.
          {stdout, 0} -> not String.contains?(stdout, "INFO:")
          _ -> false
        end

      _ ->
        case System.cmd("kill", ["-0", pid_string], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end
    end
  rescue
    _ -> true
  end

  defp shutdown do
    # Spawn a separate process so we don't block the GenServer exit
    # path — System.stop/1 is synchronous and calls back through the
    # supervisor tree.
    spawn(fn -> System.stop(0) end)
  end
end
