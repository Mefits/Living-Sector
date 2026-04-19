defmodule Simulator.Economy.Recipes do
  @moduledoc """
  Production recipes that transform input commodities into outputs.

  Each recipe defines what a facility type can produce, what inputs it
  needs, and the conversion ratio. Facilities execute recipes each tick
  if they have sufficient input supply.

  ## Recipe Structure

      %{
        id: :smelt_metals,
        name: "Smelt Metals",
        facility_type: :refinery,
        inputs: %{ore: 10, fuel: 2},
        outputs: %{metals: 5},
        ticks_per_cycle: 1,
        efficiency_base: 1.0
      }

  ## Design

  Recipes are pure data — no side effects. The FacilityAgent reads
  available recipes for its type and executes them against local
  market supply. If inputs are insufficient, partial production
  happens (scaled by available fraction).
  """

  @type recipe :: %{
          id: atom(),
          name: String.t(),
          facility_type: atom(),
          inputs: %{atom() => pos_integer()},
          outputs: %{atom() => pos_integer()},
          ticks_per_cycle: pos_integer(),
          efficiency_base: float()
        }

  @recipes [
    # --- Refinery recipes (raw → refined) ---
    # Raw materials are abundant (210K ore, 132K ice, 63K gas sitting in markets)
    # so refining should convert generously to keep the pipeline flowing.
    %{
      id: :smelt_metals,
      name: "Smelt Metals",
      facility_type: :refinery,
      inputs: %{ore: 10, fuel: 1},
      outputs: %{metals: 8},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    %{
      id: :process_ice,
      name: "Process Ice",
      facility_type: :refinery,
      inputs: %{ice: 8},
      outputs: %{water: 6, fuel: 5},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    %{
      id: :crack_fuel,
      name: "Crack Fuel from Gas",
      facility_type: :refinery,
      inputs: %{gas: 6},
      outputs: %{fuel: 4},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    %{
      id: :refine_polymers,
      name: "Refine Polymers",
      facility_type: :refinery,
      inputs: %{gas: 6},
      outputs: %{polymers: 5},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    # --- Factory recipes (refined → manufactured) ---
    # Manufactured goods are chronically scarce (418 components across 23 markets).
    # Factories need to amplify value — small refined inputs → generous manufactured output.
    %{
      id: :assemble_components,
      name: "Assemble Components",
      facility_type: :factory,
      inputs: %{metals: 3, polymers: 1},
      outputs: %{components: 5},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    %{
      id: :build_electronics,
      name: "Build Electronics",
      facility_type: :factory,
      inputs: %{components: 2, metals: 1},
      outputs: %{electronics: 3},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    %{
      id: :forge_tools,
      name: "Forge Tools",
      facility_type: :factory,
      inputs: %{metals: 2, polymers: 1},
      outputs: %{tools: 4},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    # --- Farm/habitat recipes (refined → consumer) ---
    %{
      id: :grow_food,
      name: "Grow Food",
      facility_type: :farm,
      inputs: %{water: 3},
      outputs: %{food: 10},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    %{
      id: :produce_medical,
      name: "Produce Medical Supplies",
      facility_type: :factory,
      inputs: %{water: 2, components: 1},
      outputs: %{medical: 4},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    },
    %{
      id: :craft_luxury,
      name: "Craft Luxury Goods",
      facility_type: :factory,
      inputs: %{components: 2, polymers: 1},
      outputs: %{luxury: 1},
      ticks_per_cycle: 1,
      efficiency_base: 1.0
    }
  ]

  @doc """
  Returns all defined recipes.
  """
  @spec all() :: [recipe()]
  def all, do: @recipes

  @doc """
  Returns recipes available to a given facility type.
  """
  @spec for_facility_type(atom()) :: [recipe()]
  def for_facility_type(facility_type) do
    Enum.filter(@recipes, &(&1.facility_type == facility_type))
  end

  @doc """
  Returns a recipe by ID.
  """
  @spec get(atom()) :: recipe() | nil
  def get(recipe_id) do
    Enum.find(@recipes, &(&1.id == recipe_id))
  end

  @doc """
  Executes a recipe against available supply, returning the updated supply
  and how much was produced. Handles partial production when inputs are
  scarce — scales output by the limiting input fraction.

  Returns `{updated_supply, produced_outputs}`.

  ## Examples

      iex> supply = %{ore: 100, fuel: 20}
      iex> recipe = Recipes.get(:smelt_metals)
      iex> {new_supply, produced} = Recipes.execute(recipe, supply, 1.0)
      iex> produced.metals
      5
  """
  @spec execute(recipe(), map(), float(), pos_integer()) :: {map(), map()}
  def execute(recipe, supply, efficiency \\ 1.0, max_batches \\ 50) do
    # Find the limiting factor — what fraction of the recipe can we run?
    scale =
      recipe.inputs
      |> Enum.map(fn {commodity, needed} ->
        available = Map.get(supply, commodity, 0)
        if needed > 0, do: available / needed, else: 999.0
      end)
      |> Enum.min(fn -> 0.0 end)
      |> min(max_batches * 1.0)
      |> max(0.0)

    if scale <= 0.0 do
      {supply, %{}}
    else
      effective_scale = scale * efficiency * recipe.efficiency_base

      # Skip if any output would round to zero — don't waste inputs for nothing
      outputs_viable =
        Enum.all?(recipe.outputs, fn {_, amount} ->
          round(amount * effective_scale) > 0
        end)

      if not outputs_viable do
        {supply, %{}}
      else
        # Consume inputs (scaled)
        supply_after_inputs =
          Enum.reduce(recipe.inputs, supply, fn {commodity, amount}, acc ->
            consumed = round(amount * scale)
            Map.update(acc, commodity, 0, &max(&1 - consumed, 0))
          end)

        # Produce outputs (scaled)
        {supply_after_outputs, produced} =
          Enum.reduce(recipe.outputs, {supply_after_inputs, %{}}, fn {commodity, amount},
                                                                     {sup, prod} ->
            output = round(amount * effective_scale)
            new_sup = Map.update(sup, commodity, output, &(&1 + output))
            new_prod = Map.put(prod, commodity, output)
            {new_sup, new_prod}
          end)

        {supply_after_outputs, produced}
      end
    end
  end
end
