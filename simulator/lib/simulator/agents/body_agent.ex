defmodule Simulator.Agents.BodyAgent do
  @moduledoc """
  Agent that models the natural behaviour of a celestial body.

  A BodyAgent owns the mutable portion of a body's state that the
  SystemAgent doesn't care about: biome-driven production into
  co-located markets, resource depletion under extraction, and slow
  regeneration back toward seed richness.

  ## Production

  Each tick, a body whose biome has a renewable production profile
  (e.g., a terrestrial planet produces food/water) adds a small amount
  to each co-located market. Output scales with the aggregated
  population of facilities on the body so richer worlds produce more,
  but a floor term keeps even uninhabited bodies generating a trickle
  so markets don't starve before pops spin up.

  ## Extraction & Regen

  Mining rigs call `extract/3` to pull commodities from the body's
  resource pool instead of reading a static richness number. Each
  extract decrements the current richness for that commodity. A slow
  per-tick regen phase moves levels back toward the seed value so
  bodies recover after mining lulls.

  ## Pop Feedback

  `food_availability_multiplier/1` returns a number in ~[0.5, 2.0] based
  on how much food the body produced in its recent window. PopAgent
  multiplies this into its growth_rate, closing the second feedback
  loop from the Phase 3 plan: abundant food encourages pop growth,
  starvation slows it.
  """

  use Simulator.Agents.Agent

  alias Simulator.Agents.{BodyAgent.BiomeProfiles, MarketAgent}

  # How often the body's production phase runs. Kept coarser than the
  # tick interval to avoid drowning markets in single-unit injections.
  @production_interval 5 * Simulator.Simulation.Config.tick_multiplier()
  # Regen moves current richness back toward seed at this fraction per
  # tick. Kept small so mining reductions are meaningful but bodies do
  # heal over long timescales.
  @regen_rate 0.0005
  # Rolling window over which to measure recent food output for the
  # pop-growth feedback multiplier.
  @food_window_ticks 200 * Simulator.Simulation.Config.tick_multiplier()

  # --- Public API ---

  @doc """
  Returns the full body state. Used by the dashboard inspector.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc """
  Returns the current resource richness map. Unlike the seed values on
  the SystemAgent, this reflects depletion from extraction.
  """
  @spec get_resources(pid()) :: %{atom() => float()}
  def get_resources(pid), do: GenServer.call(pid, :get_resources)

  @doc """
  Attempts to extract `amount` units of `commodity` from the body.

  Returns the actual amount extracted, which may be less than the
  request if the body is depleted. Resource richness is reduced in
  proportion to the extraction — mining rigs drain the world.

  Uses a short (500ms) timeout so a mining rig never blocks on a busy
  body for more than a tick's worth of real time. On timeout or crash,
  returns 0 — the caller should treat that as "skip depletion this
  cycle" and fall back to its non-depleting default yield.
  """
  @spec extract(pid(), atom(), number()) :: number()
  def extract(pid, commodity, amount)
      when is_atom(commodity) and is_number(amount) and amount > 0 do
    GenServer.call(pid, {:extract, commodity, amount}, 500)
  catch
    :exit, _ -> 0
  end

  def extract(_pid, _commodity, _amount), do: 0

  @doc """
  Returns a growth multiplier in ~[0.5, 2.0] based on recent food output
  relative to the body's population. PopAgent multiplies this into its
  base growth_rate to close the food-driven feedback loop.
  """
  @spec food_availability_multiplier(pid()) :: float()
  def food_availability_multiplier(pid) do
    GenServer.call(pid, :food_availability_multiplier)
  end

  # --- Agent Callbacks ---

  @impl Simulator.Agents.Agent
  def agent_type, do: :body

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    biome = normalize_biome(config[:biome])
    seed_resources = numericize_resources(config[:resources] || %{})

    state = %{
      id: config.id,
      body_id: config.body_id,
      name: config[:name] || config.body_id,
      biome: biome,
      seed_resources: seed_resources,
      # Current richness per commodity — depletes from extraction, regens over time.
      resources: seed_resources,
      # Stable list of location names on this body. Used to find co-located
      # markets to push production into each tick.
      locations: config[:locations] || [],
      # Rolling window of recent food output: [{tick, qty}]. Used to compute
      # food_availability_multiplier/1 for pop growth feedback.
      food_output_window: [],
      last_tick: 0,
      __db_id__: config[:db_id],
      __agent_type__: :body
    }

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def handle_tick(tick, state) do
    state =
      state
      |> phase_production(tick)
      |> phase_regen(tick)
      |> Map.put(:last_tick, tick)

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def persist_state(state) do
    if db_id = state[:__db_id__] do
      Simulator.Repo.get!(Simulator.Schemas.CelestialBody, db_id)
      |> Simulator.Schemas.CelestialBody.changeset(%{
        state: %{
          "resources" => stringify_keys(state.resources),
          "last_tick" => state.last_tick
        }
      })
      |> Simulator.Repo.update!()
    end

    :ok
  end

  # --- GenServer Handlers ---

  @impl GenServer
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:get_resources, _from, state), do: {:reply, state.resources, state}

  def handle_call({:extract, commodity, amount}, _from, state) do
    current = Map.get(state.resources, commodity, 0.0)

    if current <= 0.0 do
      {:reply, 0, state}
    else
      # Extraction consumes a fraction of richness proportional to the amount
      # requested. 1.0 unit of ore at richness 0.7 draws the richness down
      # by @richness_drain_per_unit — depletion is gradual, not cliff-edged.
      drain = amount * richness_drain_per_unit(commodity)
      new_richness = max(current - drain, 0.0)

      # Actual yield scales with current richness so a nearly-depleted body
      # gives less per attempt, and the caller's request acts as an upper bound.
      actual = min(amount, amount * current)
      new_resources = Map.put(state.resources, commodity, new_richness)

      {:reply, actual, %{state | resources: new_resources}}
    end
  end

  def handle_call(:food_availability_multiplier, _from, state) do
    {:reply, compute_food_multiplier(state), state}
  end

  # --- Tick Phases ---

  defp phase_production(state, tick) when rem(tick, @production_interval) == 0 do
    profile = BiomeProfiles.production_profile(state.biome)

    if profile == %{} do
      state
    else
      pop_scale = compute_pop_scale(state)
      produced = produce_into_markets(state, profile, pop_scale, tick)

      # Track food output for the pop-growth feedback multiplier.
      food_qty = Map.get(produced, :food, 0)

      window =
        [{tick, food_qty} | state.food_output_window]
        |> Enum.reject(fn {t, _q} -> t < tick - @food_window_ticks end)

      state = %{state | food_output_window: window}

      # Publish the current food multiplier for PopAgent subscribers. Broadcasting
      # here instead of letting pops call us avoids a sync fan-in that could
      # deadlock under heavy load.
      broadcast_food_multiplier(state)

      state
    end
  end

  defp phase_production(state, _tick), do: state

  defp broadcast_food_multiplier(state) do
    mult = compute_food_multiplier(state)

    Simulator.Events.broadcast("body:#{state.body_id}", :food_availability, %{
      body_id: state.body_id,
      multiplier: mult,
      tick: state.last_tick
    })
  end

  defp compute_food_multiplier(state) do
    recent_food = recent_output(state.food_output_window, state.last_tick, @food_window_ticks)

    cond do
      recent_food == 0 ->
        1.0

      true ->
        expected = expected_food_over_window(state)

        if expected <= 0.0 do
          1.0
        else
          ratio = recent_food / expected
          ratio |> max(0.5) |> min(2.0)
        end
    end
  end

  defp phase_regen(state, tick) when rem(tick, @production_interval) == 0 do
    new_resources =
      Map.new(state.seed_resources, fn {commodity, seed} ->
        current = Map.get(state.resources, commodity, seed)

        # Simple exponential regen toward seed: current moves 0.05% of the
        # remaining gap each regen tick. Takes a long time to fully recover
        # a depleted body but keeps the trend in the right direction.
        new_value = current + (seed - current) * @regen_rate
        {commodity, max(new_value, 0.0)}
      end)

    %{state | resources: new_resources}
  rescue
    _ -> state
  end

  defp phase_regen(state, _tick), do: state

  # --- Production Helpers ---

  defp produce_into_markets(state, profile, pop_scale, _tick) do
    markets = resolve_markets(state.locations)

    Enum.reduce(profile, %{}, fn {commodity, base_rate}, acc ->
      # Small floor so uninhabited-but-inhabitable worlds still drip goods.
      effective_scale = 0.25 + pop_scale * 0.75
      amount = round(base_rate * effective_scale * @production_interval)

      if amount > 0 and markets != [] do
        # Split evenly across co-located markets so a body with multiple
        # facilities (e.g., Earth: station + farm + factory) spreads supply.
        per_market = max(div(amount, length(markets)), 1)

        Enum.each(markets, fn market_pid ->
          MarketAgent.add_supply(market_pid, %{commodity => per_market})
        end)

        Map.put(acc, commodity, amount)
      else
        acc
      end
    end)
  end

  defp resolve_markets(locations) do
    Enum.flat_map(locations, fn loc ->
      case Simulator.Agents.Agent.whereis("market-#{loc}") do
        {:ok, pid} -> [pid]
        :error -> []
      end
    end)
  end

  # Returns a scale factor for organic production based on whether any pops
  # are registered at co-located facilities. Uses only the Registry key scan
  # (no GenServer.calls into pop agents), so the body's tick never blocks on
  # a slow pop — the sync fanout this replaced could deadlock under load.
  #
  # Coarse-grained on purpose: populated → 1.0, uninhabited → 0.3. That fits
  # the conservative feedback band from the Phase 3 plan; a more granular
  # model can poll pop counts into an ETS cache asynchronously later.
  defp compute_pop_scale(state) do
    if any_pops_registered?(state.locations), do: 1.0, else: 0.3
  end

  defp any_pops_registered?(locations) do
    prefixes = Enum.map(locations, &("pop-" <> &1))

    Registry.select(Simulator.AgentRegistry, [
      {{{:agent, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
    |> Enum.any?(fn agent_id ->
      Enum.any?(prefixes, &String.starts_with?(agent_id, &1))
    end)
  end

  # How much the richness map drops per unit extracted. Higher values mean
  # faster depletion. Tuned so a busy mining rig could noticeably deplete
  # a low-richness body over ~thousands of ticks.
  defp richness_drain_per_unit(_commodity), do: 0.0001

  # Expected food output over the window at pop_scale = 1.0. Used as the
  # denominator in food_availability_multiplier so the returned multiplier
  # is centred around 1.0 when the body is producing at its expected rate.
  defp expected_food_over_window(state) do
    profile = BiomeProfiles.production_profile(state.biome)
    base_rate = Map.get(profile, :food, 0.0)
    # Effective scale at pop_scale = 1.0 matches produce_into_markets above.
    effective_scale = 0.25 + 1.0 * 0.75

    per_production_tick = base_rate * effective_scale * @production_interval
    production_ticks_per_window = div(@food_window_ticks, @production_interval)

    per_production_tick * production_ticks_per_window
  end

  defp recent_output(window, _now, _ticks_back) do
    Enum.reduce(window, 0, fn {_t, q}, acc -> acc + q end)
  end

  defp normalize_biome(nil), do: nil
  defp normalize_biome(biome) when is_atom(biome), do: biome

  defp normalize_biome(biome) when is_binary(biome) do
    case biome do
      "terrestrial" -> :terrestrial
      "ocean" -> :ocean
      "desert" -> :desert
      "ice" -> :ice
      "ice_moon" -> :ice
      "lifeless" -> :lifeless
      "asteroid" -> :asteroid
      "gas_giant" -> :gas_giant
      "molten" -> :molten
      "industrial" -> :industrial
      _ -> nil
    end
  end

  defp numericize_resources(resources) when is_map(resources) do
    Map.new(resources, fn
      {k, v} when is_binary(k) ->
        {String.to_existing_atom(k), to_number(v)}

      {k, v} ->
        {k, to_number(v)}
    end)
  rescue
    _ -> %{}
  end

  defp numericize_resources(_), do: %{}

  defp to_number(n) when is_float(n), do: n
  defp to_number(n) when is_integer(n), do: n * 1.0
  defp to_number(_), do: 0.0

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
