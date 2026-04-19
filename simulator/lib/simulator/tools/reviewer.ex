defmodule Simulator.Tools.Reviewer do
  @moduledoc """
  CLI tool for inspecting simulation health and tailing events.

  Use from `iex -S mix phx.server`:

      Simulator.Tools.Reviewer.report()       # full health summary
      Simulator.Tools.Reviewer.health_check()  # :ok or {:problems, [...]}
      Simulator.Tools.Reviewer.tail("tick")    # tail events on a topic

  Designed so Claude (or a developer) can verify the simulation is
  behaving correctly without using the browser dashboard.
  """

  alias Simulator.{Queries, TickCoordinator, Metrics}

  @price_warning_threshold 500
  @credits_warning_threshold 50_000

  @doc """
  Prints a formatted health report of the simulation to stdout.
  """
  @spec report() :: :ok
  def report do
    IO.puts("\n#{header("SIMULATION HEALTH REPORT")}")

    report_tick_status()
    report_agent_counts()
    report_markets()
    report_ships()
    report_facilities()
    report_metrics()

    case health_check() do
      :ok ->
        IO.puts("\n#{color(:green, "✓ ALL CHECKS PASSED")}\n")

      {:problems, problems} ->
        IO.puts("\n#{color(:red, "✗ #{length(problems)} PROBLEM(S) FOUND:")}")
        Enum.each(problems, &IO.puts("  #{color(:red, "• #{&1}")}"))
        IO.puts("")
    end

    :ok
  end

  @doc """
  Returns `:ok` if the simulation is healthy, or `{:problems, [descriptions]}`
  if issues are detected.
  """
  @spec health_check() :: :ok | {:problems, [String.t()]}
  def health_check do
    problems =
      []
      |> check_tick_running()
      |> check_prices_sane()
      |> check_credits_sane()
      |> check_supply_exists()
      |> check_no_stalled_agents()

    case problems do
      [] -> :ok
      list -> {:problems, list}
    end
  end

  @doc """
  Subscribes to a PubSub topic and prints events to the console as they arrive.

  Returns a function that stops tailing when called.

  ## Examples

      stop = Simulator.Tools.Reviewer.tail("tick")
      # ... events print to console ...
      stop.()

      stop = Simulator.Tools.Reviewer.tail("market:earth-station")
      stop.()
  """
  @spec tail(String.t()) :: (-> :ok)
  def tail(topic) do
    {:ok, pid} =
      Task.start(fn ->
        Simulator.Events.subscribe(topic)
        IO.puts("#{color(:cyan, "▶ Tailing")} #{topic} (call stop.() to end)")
        tail_loop(topic)
      end)

    fn ->
      Process.exit(pid, :normal)
      IO.puts("#{color(:cyan, "■ Stopped")} tailing #{topic}")
      :ok
    end
  end

  # --- Report Sections ---

  defp report_tick_status do
    tick = TickCoordinator.get_tick()
    running = TickCoordinator.running?()
    status = if running, do: color(:green, "RUNNING"), else: color(:yellow, "PAUSED")
    IO.puts("#{label("Status")} #{status}  #{label("Tick")} #{tick}")
  end

  defp report_agent_counts do
    metrics = Metrics.snapshot()
    counts = metrics.agents.counts
    total = metrics.agents.total
    IO.puts("#{label("Agents")} #{total} total — #{inspect(counts)}")
  end

  defp report_markets do
    IO.puts("\n#{header("MARKETS")}")
    Enum.each(Queries.all_markets(), &print_market/1)
  end

  defp print_market(market) do
    IO.puts("  #{color(:bold, market.facility_id)}")
    Enum.each([:ore, :fuel, :food], &print_commodity(market, &1))
  end

  defp print_commodity(market, commodity) do
    price = Map.get(market.prices, commodity, 0)
    supply = Map.get(market.supply, commodity, 0)
    demand = Map.get(market.demand, commodity, 0)

    flag =
      if is_number(price) and price > @price_warning_threshold, do: color(:red, " ⚠"), else: ""

    IO.puts(
      "    #{String.pad_trailing(to_string(commodity), 6)} " <>
        "price: #{String.pad_leading(format_num(price), 8)}  " <>
        "supply: #{String.pad_leading(to_string(supply), 6)}  " <>
        "demand: #{String.pad_leading(to_string(demand), 6)}#{flag}"
    )
  end

  defp report_ships do
    IO.puts("\n#{header("SHIPS")}")

    for ship <- Queries.all_ships() do
      location = ship.location || "→ #{ship.transit && ship.transit.to}"

      plan_type = Map.get(ship, :current_goal)

      flag = if ship.credits > @credits_warning_threshold, do: color(:red, " ⚠"), else: ""

      IO.puts(
        "  #{String.pad_trailing(ship.name, 18)} " <>
          "#{String.pad_trailing(location, 18)} " <>
          "credits: #{String.pad_leading(format_num(ship.credits), 8)}  " <>
          "fuel: #{String.pad_leading(format_num(ship.fuel), 6)}  " <>
          "plan: #{plan_type || "—"}#{flag}"
      )
    end
  end

  defp report_facilities do
    IO.puts("\n#{header("FACILITIES")}")

    for f <- Queries.all_facilities() do
      IO.puts(
        "  #{String.pad_trailing(f.name, 22)} " <>
          "docked: #{length(f.docked_ships)}/#{f.docking_capacity}  " <>
          "condition: #{Float.round(f.condition, 2)}  " <>
          "credits: #{format_num(f.credits)}"
      )
    end
  end

  defp report_metrics do
    IO.puts("\n#{header("PERFORMANCE")}")
    m = Metrics.snapshot()

    IO.puts(
      "  Tick avg: #{format_us(m.tick.avg_duration_us)}  " <>
        "p99: #{format_us(m.tick.p99_duration_us)}  " <>
        "tps: #{m.tick.ticks_per_second}  " <>
        "stalled: #{length(m.agents.stalled)}"
    )
  end

  # --- Health Checks ---

  defp check_tick_running(problems) do
    if TickCoordinator.running?(), do: problems, else: ["Tick coordinator not running" | problems]
  end

  defp check_prices_sane(problems) do
    bad_prices =
      for market <- Queries.all_markets(),
          {commodity, price} <- market.prices,
          is_number(price) and price > @price_warning_threshold do
        "#{market.facility_id} #{commodity} price is #{format_num(price)} (> #{@price_warning_threshold})"
      end

    bad_prices ++ problems
  end

  defp check_credits_sane(problems) do
    Queries.all_ships()
    |> Enum.reduce(problems, fn ship, acc ->
      cond do
        ship.credits > @credits_warning_threshold ->
          [
            "#{ship.name} credits #{format_num(ship.credits)} (> #{@credits_warning_threshold})"
            | acc
          ]

        ship.credits < 0 ->
          ["#{ship.name} credits negative: #{ship.credits}" | acc]

        true ->
          acc
      end
    end)
  end

  defp check_supply_exists(problems) do
    all_zero? =
      Queries.all_markets()
      |> Enum.all?(fn m ->
        Enum.all?(m.supply, fn {_k, v} -> v == 0 end)
      end)

    if all_zero?, do: ["All markets have zero supply" | problems], else: problems
  end

  defp check_no_stalled_agents(problems) do
    stalled = Metrics.snapshot().agents.stalled

    if stalled != [] do
      ids = Enum.map_join(stalled, ", ", & &1.id)
      ["#{length(stalled)} stalled agents: #{ids}" | problems]
    else
      problems
    end
  end

  # --- Tail Loop ---

  defp tail_loop(topic) do
    receive do
      {event, payload} when is_atom(event) ->
        ts = DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")

        IO.puts(
          "#{color(:dim, ts)} #{color(:cyan, "[#{topic}]")} #{color(:bold, to_string(event))} #{inspect(payload, pretty: false, limit: 5)}"
        )

        tail_loop(topic)

      other ->
        IO.puts("#{color(:dim, "???")} #{inspect(other)}")
        tail_loop(topic)
    end
  end

  # --- Formatting ---

  defp header(text), do: color(:bold, "═══ #{text} ═══")
  defp label(text), do: color(:dim, "#{text}:")

  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)

  defp format_num(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  defp format_num(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_num(n), do: to_string(n)

  defp format_us(us) when is_number(us) and us >= 1000, do: "#{Float.round(us / 1000, 1)}ms"
  defp format_us(us) when is_number(us), do: "#{round(us)}µs"
  defp format_us(_), do: "—"

  defp color(:red, text), do: IO.ANSI.red() <> text <> IO.ANSI.reset()
  defp color(:green, text), do: IO.ANSI.green() <> text <> IO.ANSI.reset()
  defp color(:yellow, text), do: IO.ANSI.yellow() <> text <> IO.ANSI.reset()
  defp color(:cyan, text), do: IO.ANSI.cyan() <> text <> IO.ANSI.reset()
  defp color(:bold, text), do: IO.ANSI.bright() <> text <> IO.ANSI.reset()
  defp color(:dim, text), do: IO.ANSI.faint() <> text <> IO.ANSI.reset()
end
