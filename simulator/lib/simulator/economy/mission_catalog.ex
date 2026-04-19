defmodule Simulator.Economy.MissionCatalog do
  @moduledoc """
  Static catalog of crew-mission templates.

  Each facility type has a set of missions it can post — a mining rig
  looking for heavy maintenance, a station looking for security detail,
  a farm needing harvest help. A mission template carries everything
  needed to post a contract and later pay it out: duration, payment,
  which crew skill grows on completion, and by how much.

  The catalog is code-driven on purpose. v1 is small enough that a JSON
  layer would add friction without much payoff; we can promote to data
  files later if the list gets unwieldy or players need to author
  custom missions.

  ## Shape

  Each entry is a map with:

    * `:category` — atom identifier (e.g., `:security_detail`)
    * `:display_name` — human-readable label for UI
    * `:posted_by` — list of facility type atoms that post this mission
    * `:duration_ticks` — tick count for the wait phase (not yet scaled)
    * `:base_payment` — credits awarded on completion
    * `:required_skill` — crew skill atom the mission exercises
    * `:skill_gain` — amount added to the crew's `required_skill` on completion

  Duration is expressed in "game ticks" — the caller multiplies by
  `Simulator.Simulation.Config.tick_multiplier/0` at post time so the
  wall-clock feel stays consistent as we tune the tick rate.
  """

  @type category :: atom()
  @type mission :: %{
          category: category(),
          display_name: String.t(),
          posted_by: [atom()],
          duration_ticks: pos_integer(),
          base_payment: pos_integer(),
          required_skill: atom(),
          skill_gain: pos_integer()
        }

  @catalog [
    %{
      category: :security_detail,
      display_name: "Security Detail",
      posted_by: [:station],
      duration_ticks: 30,
      base_payment: 1500,
      required_skill: :combat,
      skill_gain: 3
    },
    %{
      category: :vip_escort,
      display_name: "VIP Escort",
      posted_by: [:station],
      duration_ticks: 20,
      base_payment: 1200,
      required_skill: :navigation,
      skill_gain: 2
    },
    %{
      category: :customs_assist,
      display_name: "Customs Assist",
      posted_by: [:station],
      duration_ticks: 15,
      base_payment: 800,
      required_skill: :trading,
      skill_gain: 2
    },
    %{
      category: :heavy_maintenance,
      display_name: "Heavy Maintenance",
      posted_by: [:mining_rig, :refinery],
      duration_ticks: 40,
      base_payment: 2000,
      required_skill: :engineering,
      skill_gain: 3
    },
    %{
      category: :salvage_operation,
      display_name: "Salvage Operation",
      posted_by: [:mining_rig],
      duration_ticks: 35,
      base_payment: 1800,
      required_skill: :engineering,
      skill_gain: 2
    },
    %{
      category: :production_assist,
      display_name: "Production Assist",
      posted_by: [:factory],
      duration_ticks: 25,
      base_payment: 1400,
      required_skill: :engineering,
      skill_gain: 2
    },
    %{
      category: :equipment_calibration,
      display_name: "Equipment Calibration",
      posted_by: [:factory, :refinery],
      duration_ticks: 20,
      base_payment: 1100,
      required_skill: :engineering,
      skill_gain: 2
    },
    %{
      category: :harvest_help,
      display_name: "Harvest Help",
      posted_by: [:farm],
      duration_ticks: 30,
      base_payment: 1200,
      required_skill: :general,
      skill_gain: 1
    },
    %{
      category: :safety_audit,
      display_name: "Safety Audit",
      posted_by: [:refinery],
      duration_ticks: 25,
      base_payment: 1500,
      required_skill: :engineering,
      skill_gain: 2
    }
  ]

  @doc """
  Returns every mission template in the catalog.
  """
  @spec all() :: [mission()]
  def all, do: @catalog

  @doc """
  Returns the templates a facility of `facility_type` can post.

  Unknown types return `[]` — no crash, just no missions for that
  facility.
  """
  @spec for_facility_type(atom() | String.t() | nil) :: [mission()]
  def for_facility_type(nil), do: []

  def for_facility_type(facility_type) when is_atom(facility_type) do
    Enum.filter(@catalog, &(facility_type in &1.posted_by))
  end

  def for_facility_type(facility_type) when is_binary(facility_type) do
    try do
      for_facility_type(String.to_existing_atom(facility_type))
    rescue
      ArgumentError -> []
    end
  end

  @doc """
  Returns the template for a given category atom, or `nil` if unknown.

  Accepts both the atom form (`:security_detail`) and the string form
  (`"security_detail"`) — the latter shows up on the wire when a contract
  is round-tripped through JSON.
  """
  @spec get(atom() | String.t() | nil) :: mission() | nil
  def get(nil), do: nil

  def get(category) when is_atom(category) do
    Enum.find(@catalog, &(&1.category == category))
  end

  def get(category) when is_binary(category) do
    try do
      get(String.to_existing_atom(category))
    rescue
      ArgumentError -> nil
    end
  end

  @doc """
  Returns the list of known facility types that have at least one mission.
  """
  @spec supported_facility_types() :: [atom()]
  def supported_facility_types do
    @catalog
    |> Enum.flat_map(& &1.posted_by)
    |> Enum.uniq()
  end
end
