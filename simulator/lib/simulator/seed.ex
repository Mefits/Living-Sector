defmodule Simulator.Seed do
  @moduledoc """
  Loads world data from JSON files into Postgres.

  Upserts on ID — re-running `mix seed` updates existing records and
  inserts new ones without duplicating. Safe to run repeatedly.

  ## Usage

      Simulator.Seed.seed_all()           # seed everything from priv/data/
      Simulator.Seed.seed_factions(path)  # seed factions from a JSON file
      Simulator.Seed.seed_world(path)     # seed a star system from a JSON file
  """

  require Logger

  alias Simulator.Repo

  alias Simulator.Schemas.{
    CelestialBody,
    Facility,
    Faction,
    Location,
    Market,
    Population,
    Ship,
    StarSystem
  }

  @doc """
  Seeds everything from the default data directory.
  """
  def seed_all do
    # `Application.app_dir/2` resolves correctly in both dev (project
    # `priv/`) and a release (`lib/simulator-<vsn>/priv/`). Relative
    # paths fail in release because CWD isn't the project root when
    # Godot spawns the sim.
    data_dir = Application.app_dir(:simulator, "priv/data")

    Logger.info("Seed: loading factions...")
    seed_factions(Path.join(data_dir, "factions.json"))

    Logger.info("Seed: loading worlds...")

    for world_file <- Path.wildcard(Path.join([data_dir, "worlds", "*.json"])) do
      Logger.info("Seed: loading #{Path.basename(world_file)}...")
      seed_world(world_file)
    end

    Logger.info("Seed: complete!")
  end

  @doc """
  Seeds factions from a JSON file.
  """
  def seed_factions(path) do
    path
    |> read_json()
    |> Enum.each(fn faction_data ->
      attrs = atomize_keys(faction_data)

      %Faction{}
      |> Faction.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: :id
      )
    end)
  end

  @doc """
  Seeds a star system and all its entities from a JSON file.
  """
  def seed_world(path) do
    data = read_json(path)

    # 1. System
    system_data = data["system"]
    [ox, oy] = system_data["universe_offset"] || data["universe_offset"] || [0.0, 0.0]

    upsert!(
      StarSystem,
      %{
        name: system_data["name"],
        universe_offset_x: ox,
        universe_offset_y: oy
      },
      :name
    )
    |> then(fn system ->
      system_id = system.id

      # 2. Bodies — build a json_id → DB record map for facility lookups
      body_map =
        Enum.reduce(data["bodies"] || [], %{}, fn body_data, acc ->
          record =
            upsert!(
              CelestialBody,
              %{
                body_id: body_data["id"],
                name: body_data["name"],
                type: body_data["type"],
                orbit_radius: body_data["orbit_radius"],
                orbit_period: body_data["orbit_period"],
                current_angle: body_data["current_angle"] || 0.0,
                resources: body_data["resources"] || %{},
                biome: body_data["biome"],
                star_system_id: system_id
              },
              :name
            )

          Map.put(acc, body_data["id"], record)
        end)

      # 3. Facilities (need location + body references)
      for facility_data <- data["facilities"] || [] do
        # Look up body by the JSON id (e.g., "earth", "belt", "haven")
        body = Map.get(body_map, facility_data["body"])
        body_id = if body, do: body.id, else: nil

        location =
          upsert!(
            Location,
            %{
              name: facility_data["location"],
              type: facility_data["type"],
              celestial_body_id: body_id
            },
            :name
          )

        services =
          (facility_data["services"] || [])
          |> Enum.map(&to_string/1)

        reserves = stringify_map(facility_data["reserves"] || %{})

        # Facility names aren't globally unique anymore (god-mode can
        # spawn duplicates); identify by (location_id, name) which is
        # naturally unique in the seed data. Skip if already present.
        import Ecto.Query, only: [from: 2]

        existing =
          Repo.one(
            from f in Facility,
              where: f.location_id == ^location.id and f.name == ^facility_data["name"],
              limit: 1
          )

        unless existing do
          Repo.insert!(%Facility{
            name: facility_data["name"],
            type: facility_data["type"],
            location_id: location.id,
            faction_id: facility_data["faction_id"],
            body_id: facility_data["body"],
            docking_capacity: facility_data["docking_capacity"] || 5,
            services: services,
            condition: 1.0,
            reputation: 50,
            credits: 10_000,
            initial_reserves: reserves,
            state: %{"reserves" => reserves}
          })
        end
      end

      # 4. Markets
      for market_data <- data["markets"] || [] do
        prices = stringify_map(market_data["prices"] || %{})
        supply = stringify_map(market_data["supply"] || %{})
        demand = stringify_map(market_data["demand"] || %{})
        consumption = stringify_map(market_data["consumption"] || %{})

        # Find the first facility at this location
        import Ecto.Query
        location = Repo.get_by(Location, name: market_data["facility_id"])

        facility =
          if location do
            Repo.one(from f in Facility, where: f.location_id == ^location.id, limit: 1)
          end

        if facility do
          upsert!(
            Market,
            %{
              facility_id: facility.id,
              facility_location: market_data["facility_id"],
              prices: prices,
              supply: supply,
              demand: demand,
              production: stringify_map(market_data["production"] || %{}),
              consumption: consumption,
              price_elasticity: market_data["price_elasticity"] || 0.02,
              spread: 0.10,
              state: %{}
            },
            :facility_id
          )
        end
      end

      # 5. Ships
      for ship_data <- data["ships"] || [] do
        _ship_id =
          ship_data["name"]
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]/, "-")

        class = ship_data["class"] || "freighter"
        class_stats = Simulator.Simulation.Config.ship_classes()[String.to_existing_atom(class)]

        location = Repo.get_by(Location, name: ship_data["location"])

        # Ship names aren't globally unique anymore (admin god-mode can
        # spawn duplicates). For seed idempotency: if a ship with this
        # name already lives in the JSON-seeded faction, leave it alone.
        existing = Repo.get_by(Ship, name: ship_data["name"])

        unless existing do
          Repo.insert!(%Ship{
            name: ship_data["name"],
            class: class,
            location_id: if(location, do: location.id),
            cargo: %{},
            cargo_capacity: class_stats.cargo_capacity,
            fuel: class_stats.fuel_capacity,
            fuel_capacity: class_stats.fuel_capacity,
            fuel_consumption_rate: class_stats.fuel_consumption_rate,
            credits: ship_data["credits"] || 5000,
            efficiency: 1.0,
            faction_id: ship_data["faction_id"],
            speed_modifier: class_stats.speed_modifier,
            system_id: system_data["id"],
            universe_offset_x: ox,
            universe_offset_y: oy,
            state: %{}
          })
        end
      end

      # 6. Populations
      for pop_data <- data["populations"] || [] do
        import Ecto.Query
        location = Repo.get_by(Location, name: pop_data["facility_id"])

        facility =
          if location do
            Repo.one(from f in Facility, where: f.location_id == ^location.id, limit: 1)
          end

        if facility do
          Repo.insert(
            %Population{
              label: pop_data["label"],
              demographic: pop_data["demographic"],
              facility_id: facility.id,
              faction_id: pop_data["faction_id"],
              population_count: pop_data["population_count"] || 10_000,
              overall_sentiment: 50,
              unrest: 0,
              total_wealth: pop_data["total_wealth"] || 500_000,
              food_satisfaction: pop_data["food_satisfaction"] || 50,
              consumption: stringify_map(pop_data["consumption"] || %{}),
              production_commodity: pop_data["production_commodity"],
              production_amount: pop_data["production_amount"] || 0,
              growth_rate: 0.001,
              state: %{}
            },
            on_conflict: :nothing,
            conflict_target: :label
          )
        end
      end
    end)
  end

  # --- Private Helpers ---

  defp read_json(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp upsert!(schema, attrs, conflict_field) do
    # Build a list of fields to replace on conflict (all except id and inserted_at)
    replace_fields =
      Map.keys(attrs)
      |> Enum.reject(&(&1 in [:id, :inserted_at]))

    changeset = schema.__struct__() |> Ecto.Changeset.change(attrs)

    case Repo.insert(changeset,
           on_conflict: {:replace, replace_fields},
           conflict_target: conflict_field,
           returning: true
         ) do
      {:ok, record} ->
        record

      {:error, changeset} ->
        Logger.error("Seed upsert failed: #{inspect(changeset.errors)}")
        Repo.get_by(schema, [{conflict_field, attrs[conflict_field]}])
    end
  end
end
