defmodule Simulator.Agents.CrewAgent do
  @moduledoc """
  A named individual crew member with needs, skills, and opinions.

  The Dwarf Fortress dwarf of this simulation. Crew serve aboard ships
  or at stations and their collective state directly affects the performance
  of their parent entity.

  ## Needs (0-100, higher = more urgent)

    * `hunger` — rises each tick, reduced by eating (consumes food from parent)
    * `fatigue` — rises with activity, reduced by resting
    * `morale` — composite of pay, relationships, proximity to home, conditions
    * `health` — degrades from injury/illness, recovers with medical care

  ## Decision Logic

  Each tick: check needs → switch task if threshold crossed → execute task →
  periodic morale adjustment → skill growth from active task.
  """

  use Simulator.Agents.Agent

  alias Simulator.Simulation.Config

  @hunger_rate 2 * Config.tick_scale()
  @fatigue_rate_active 1 * Config.tick_scale()
  @fatigue_rate_rest -15 * Config.tick_scale()
  @hunger_eat_reduction 25 * Config.tick_scale()
  @morale_decay_rate 0.5 * Config.tick_scale()
  @skill_growth_rate 0.1 * Config.tick_scale()
  @complaint_threshold 20

  # --- Public API ---

  @doc """
  Returns the crew member's current state.
  """
  @spec get_state(pid()) :: map()
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc """
  Assigns a task to this crew member.
  """
  @spec assign_task(pid(), atom()) :: :ok
  def assign_task(pid, task), do: GenServer.call(pid, {:assign_task, task})

  @doc """
  Requests a status report (used by ShipAgent to compute efficiency).
  """
  @spec report_status(pid()) :: map()
  def report_status(pid), do: GenServer.call(pid, :report_status)

  # --- Agent Callbacks ---

  alias Simulator.AI.{Considerations, Utility}

  @defaults %{
    role: :general,
    hunger: 10,
    fatigue: 10,
    morale: 70,
    health: 100,
    skills: %{navigation: 30, engineering: 30, trading: 30, combat: 20},
    traits: [],
    current_task: :idle,
    assigned_to: nil,
    relationships: %{},
    credits: 0,
    pay_owed: 0,
    contract_expires_tick: 10_000,
    home_location: nil,
    personality: nil
  }

  # Crew task action specs for utility scoring
  @crew_actions [
    {:eating, [{:hunger_urgency, :positive}]},
    {:resting, [{:fatigue_urgency, :positive}, {:morale_concern, :positive}]},
    {:seeking_medical, [{:health_urgency, :positive}]},
    {:working,
     [{:duty_drive, :positive}, {:hunger_urgency, :negative}, {:fatigue_urgency, :negative}]},
    {:idle, []}
  ]

  @impl Simulator.Agents.Agent
  def agent_type, do: :crew

  @impl Simulator.Agents.Agent
  def init_agent(config) do
    c = Map.merge(@defaults, config)
    personality = c.personality || Simulator.AI.Personality.random_crew_personality()

    state = %{
      id: c.id,
      name: c[:name] || c.id,
      role: c.role,
      personality: personality,
      assigned_to: c.assigned_to,
      current_task: c.current_task,
      hunger: c.hunger,
      fatigue: c.fatigue,
      morale: c.morale,
      health: c.health,
      skills: c.skills,
      traits: c.traits,
      relationships: c.relationships,
      credits: c.credits,
      pay_owed: c.pay_owed,
      contract_expires_tick: c.contract_expires_tick,
      home_location: c.home_location,
      tick_count: 0,
      __db_id__: c[:db_id],
      __agent_type__: :crew
    }

    {:ok, state}
  end

  @impl Simulator.Agents.Agent
  def handle_tick(tick, state) do
    state =
      state
      |> Map.put(:tick_count, tick)
      |> select_task()
      |> execute_task()
      |> maybe_adjust_morale(tick)
      |> maybe_check_contract(tick)
      |> grow_skills()
      |> maybe_complain()
      |> mark_dirty()

    {:ok, state}
  end

  # --- GenServer Calls ---

  @impl GenServer
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call({:assign_task, task}, _from, state) do
    {:reply, :ok, %{state | current_task: task}}
  end

  def handle_call(:report_status, _from, state) do
    report = %{
      id: state.id,
      name: state.name,
      role: state.role,
      hunger: state.hunger,
      fatigue: state.fatigue,
      morale: state.morale,
      health: state.health,
      skills: state.skills
    }

    {:reply, report, state}
  end

  # --- GenServer Info Handlers ---

  @impl GenServer
  def handle_info({:wage_payment, amount}, state) do
    {:noreply,
     %{state | credits: state.credits + amount, pay_owed: max(state.pay_owed - amount, 0)}}
  end

  # --- Task Selection (Utility AI) ---

  @need_tasks [:eating, :resting, :seeking_medical]
  @work_tasks [:piloting, :navigation, :engineering, :repairing, :trading]

  defp select_task(state) do
    # Don't interrupt need-driven tasks until the need is satisfied
    if state.current_task in @need_tasks do
      state
    else
      considerations = evaluate_crew_considerations(state)
      {best_task, _score} = Utility.best_action(@crew_actions, considerations, state.personality)

      case best_task do
        task when task in @need_tasks ->
          # Urgent need overrides current work
          %{state | current_task: task}

        :working ->
          # If already on a work task, keep it. Otherwise assign role task.
          if state.current_task in @work_tasks do
            state
          else
            %{state | current_task: role_task(state.role)}
          end

        :idle ->
          # Only go idle if not already working
          if state.current_task in @work_tasks, do: state, else: %{state | current_task: :idle}
      end
    end
  end

  defp evaluate_crew_considerations(state) do
    %{
      hunger_urgency: Considerations.hunger_urgency(state),
      fatigue_urgency: Considerations.fatigue_urgency(state),
      morale_concern: Considerations.morale_concern(state),
      health_urgency: Considerations.health_urgency(state),
      # Baseline drive to work — always present, scaled by how healthy/rested
      duty_drive: {duty_drive_value(state), :loyalty}
    }
  end

  # Duty drive is high when needs are met, low when suffering
  defp duty_drive_value(state) do
    hunger_ok = max(1.0 - state.hunger / 100.0, 0.0)
    fatigue_ok = max(1.0 - state.fatigue / 100.0, 0.0)
    health_ok = state.health / 100.0
    (hunger_ok * fatigue_ok * health_ok) |> max(0.0) |> min(1.0)
  end

  defp role_task(:pilot), do: :piloting
  defp role_task(:engineer), do: :engineering
  defp role_task(:trader), do: :trading
  defp role_task(:medic), do: :idle
  defp role_task(_), do: :idle

  # --- Task Execution ---

  defp execute_task(%{current_task: :eating} = state) do
    %{state | hunger: max(state.hunger - @hunger_eat_reduction, 0)}
    |> apply_hunger_tick()
    |> maybe_resume_duty()
  end

  defp execute_task(%{current_task: :resting} = state) do
    new_fatigue = max(state.fatigue + @fatigue_rate_rest, 0)
    new_morale = min(state.morale + 1, 100)

    %{state | fatigue: new_fatigue, morale: new_morale}
    |> apply_hunger_tick()
    |> maybe_resume_duty()
  end

  defp execute_task(%{current_task: :idle} = state) do
    state
    |> apply_hunger_tick()
    |> Map.update!(:fatigue, &max(&1 - 2, 0))
  end

  defp execute_task(state) do
    # Active tasks: piloting, engineering, trading, repairing, etc.
    state
    |> apply_hunger_tick()
    |> Map.update!(:fatigue, &min(&1 + @fatigue_rate_active, 100))
  end

  defp apply_hunger_tick(state) do
    Map.update!(state, :hunger, &min(&1 + @hunger_rate, 100))
  end

  defp maybe_resume_duty(%{current_task: :eating, hunger: h} = state) when h < 30 do
    %{state | current_task: :idle}
  end

  defp maybe_resume_duty(%{current_task: :resting, fatigue: f} = state) when f < 20 do
    %{state | current_task: :idle}
  end

  defp maybe_resume_duty(state), do: state

  # --- Morale (every 5 ticks) ---

  @morale_check_interval 5 * Config.tick_multiplier()
  defp maybe_adjust_morale(state, tick) when rem(tick, @morale_check_interval) == 0 do
    needs_adj = needs_morale_adjustment(state)
    pay_adj = if state.pay_owed > 0, do: -5, else: 0
    rel_adj = relationship_morale_adjustment(state.relationships)
    drift = if state.morale > 50, do: -@morale_decay_rate, else: @morale_decay_rate

    total = needs_adj + pay_adj + rel_adj + drift
    new_morale = (state.morale + total) |> max(0) |> min(100) |> round()
    %{state | morale: new_morale}
  end

  defp maybe_adjust_morale(state, _tick), do: state

  defp needs_morale_adjustment(state) do
    cond do
      state.hunger > 60 -> -3
      state.fatigue > 70 -> -2
      state.health < 50 -> -4
      true -> 0
    end
  end

  defp relationship_morale_adjustment(relationships) do
    Enum.reduce(relationships, 0, fn {_id, sentiment}, acc ->
      cond do
        sentiment > 20 -> acc + 2
        sentiment < -20 -> acc - 3
        true -> acc
      end
    end)
  end

  # --- Skill Growth ---

  defp grow_skills(%{current_task: task} = state) when task in [:piloting, :navigation] do
    update_skill(state, :navigation)
  end

  defp grow_skills(%{current_task: task} = state) when task in [:repairing, :engineering] do
    update_skill(state, :engineering)
  end

  defp grow_skills(%{current_task: :trading} = state), do: update_skill(state, :trading)
  defp grow_skills(state), do: state

  defp update_skill(state, skill) do
    current = Map.get(state.skills, skill, 0)
    # Diminishing returns past 80
    growth = if current > 80, do: @skill_growth_rate * 0.2, else: @skill_growth_rate
    new_val = min(current + growth, 100)
    %{state | skills: Map.put(state.skills, skill, new_val)}
  end

  # --- Contract Check (every 50 ticks) ---

  @contract_check_interval 50 * Config.tick_multiplier()
  defp maybe_check_contract(state, tick) when rem(tick, @contract_check_interval) == 0 do
    if tick >= state.contract_expires_tick do
      if state.morale > 50 do
        %{state | contract_expires_tick: tick + 5_000}
      else
        notify_seeking_employment(state)
        state
      end
    else
      state
    end
  end

  defp maybe_check_contract(state, _tick), do: state

  defp notify_seeking_employment(%{assigned_to: nil}), do: :ok

  defp notify_seeking_employment(state) do
    case Simulator.Agents.Agent.whereis(state.assigned_to) do
      {:ok, pid} ->
        send(pid, {:seeking_employment, %{crew_id: state.id, role: state.role}})

      :error ->
        :ok
    end
  end

  # --- Complaints ---

  defp maybe_complain(%{morale: morale, assigned_to: parent} = state)
       when morale < @complaint_threshold and parent != nil do
    case Simulator.Agents.Agent.whereis(parent) do
      {:ok, pid} ->
        send(pid, {:crew_complaint, %{crew_id: state.id, morale: morale}})

      :error ->
        :ok
    end

    state
  end

  defp maybe_complain(state), do: state
end
