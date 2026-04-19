defmodule Simulator.Simulation.Config do
  @moduledoc """
  POC world configuration data.

  Defines the Sol system bodies, facility configs, market initial conditions,
  and ship templates. All simulation tuning parameters live here — change
  these to adjust the economy, travel, and agent behavior without touching
  any module logic.
  """

  alias Simulator.World.Body

  # --- Factions ---

  @doc """
  Returns faction definitions. Factions own facilities, employ ships/crew,
  and control contract access via reputation.
  """
  @spec factions() :: [map()]
  def factions do
    [
      %{
        id: "terran-authority",
        name: "Terran Authority",
        type: :government,
        description: "Earth's governing body. Conservative, safety-focused, well-funded.",
        home_system: "system-sol",
        personality: %{
          profit: 0.4,
          safety: 0.9,
          morale: 0.6,
          exploration: 0.2,
          loyalty: 0.8,
          aggression: 0.1
        },
        colors: %{primary: "#3b82f6", secondary: "#1e40af"}
      },
      %{
        id: "mars-syndicate",
        name: "Mars Syndicate",
        type: :corporation,
        description: "Mars industrial conglomerate. Profit-driven, aggressive expansion.",
        home_system: "system-sol",
        personality: %{
          profit: 0.9,
          safety: 0.3,
          morale: 0.2,
          exploration: 0.5,
          loyalty: 0.4,
          aggression: 0.6
        },
        colors: %{primary: "#ef4444", secondary: "#991b1b"}
      },
      %{
        id: "belt-coalition",
        name: "Belt Coalition",
        type: :coalition,
        description: "Belt workers' cooperative. Loyal, community-focused, independent.",
        home_system: "system-sol",
        personality: %{
          profit: 0.5,
          safety: 0.5,
          morale: 0.7,
          exploration: 0.3,
          loyalty: 0.9,
          aggression: 0.3
        },
        colors: %{primary: "#a3a3a3", secondary: "#525252"}
      },
      %{
        id: "frontier-ventures",
        name: "Frontier Ventures",
        type: :corporation,
        description: "Alpha Centauri exploration company. Risk-tolerant, explorer-focused.",
        home_system: "system-alpha-centauri",
        personality: %{
          profit: 0.6,
          safety: 0.3,
          morale: 0.4,
          exploration: 0.9,
          loyalty: 0.5,
          aggression: 0.2
        },
        colors: %{primary: "#f472b6", secondary: "#9d174d"}
      }
    ]
  end

  @doc """
  Returns the default faction reputation map for a new ship/crew.
  Own faction starts at 70, others at 30.
  """
  @spec default_reputation(String.t()) :: %{String.t() => integer()}
  def default_reputation(own_faction_id) do
    # Read factions from DB if available, fall back to hardcoded
    faction_ids =
      try do
        Simulator.Repo.all(Simulator.Schemas.Faction)
        |> Enum.map(& &1.id)
      rescue
        _ -> Enum.map(factions(), & &1.id)
      end

    Map.new(faction_ids, fn id ->
      rep = if id == own_faction_id, do: 70, else: 30
      {id, rep}
    end)
  end

  # --- Star Systems ---

  @doc """
  Returns the Sol system bodies configuration.
  """
  @spec sol_bodies() :: %{String.t() => Body.t()}
  def sol_bodies do
    %{
      "earth" => %Body{
        id: "earth",
        name: "Earth",
        type: :planet,
        orbit_radius: 1.0,
        orbit_period: 365,
        current_angle: 0.0,
        resources: %{ice: 0.3, gas: 0.1}
      },
      "mars" => %Body{
        id: "mars",
        name: "Mars",
        type: :planet,
        orbit_radius: 1.52,
        orbit_period: 687,
        current_angle: 45.0,
        resources: %{ore: 0.4, ice: 0.5, gas: 0.2}
      },
      "belt" => %Body{
        id: "belt",
        name: "Asteroid Belt",
        type: :belt,
        orbit_radius: 2.7,
        orbit_period: 1680,
        current_angle: 120.0,
        resources: %{ore: 0.9, ice: 0.3, gas: 0.1}
      }
    }
  end

  @doc """
  Returns facility configurations. Each facility maps to a location and body.
  """
  @spec facilities() :: [map()]
  def facilities do
    [
      # Earth — hub + farm (consumer production)
      %{
        id: "facility-earth-station",
        name: "Terra Prime Station",
        faction_id: "terran-authority",
        location: "earth-station",
        body: "earth",
        type: :station,
        docking_capacity: 10,
        services: [:refuel, :repair, :medical, :market, :passenger_terminal],
        reserves: %{fuel: 5000, food: 3000, water: 2000}
      },
      %{
        id: "facility-earth-farm",
        name: "Terra Hydroponics",
        faction_id: "terran-authority",
        location: "earth-station",
        body: "earth",
        type: :farm,
        docking_capacity: 3,
        services: [:market],
        reserves: %{water: 5000, food: 1000}
      },
      # Mars — refinery + station (converts ore/ice → metals/fuel)
      %{
        id: "facility-mars-station",
        name: "Ares Orbital",
        faction_id: "mars-syndicate",
        location: "mars-station",
        body: "mars",
        type: :station,
        docking_capacity: 8,
        services: [:refuel, :repair, :market],
        reserves: %{fuel: 4000, food: 2000, metals: 500}
      },
      %{
        id: "facility-mars-refinery",
        name: "Olympus Refinery",
        faction_id: "mars-syndicate",
        location: "mars-station",
        body: "mars",
        type: :refinery,
        docking_capacity: 4,
        services: [:market],
        reserves: %{ore: 2000, fuel: 1000, ice: 500}
      },
      # Belt — mining outpost + factory
      %{
        id: "facility-belt-outpost",
        name: "Ceres Outpost",
        faction_id: "belt-coalition",
        location: "belt-outpost",
        body: "belt",
        type: :mining_rig,
        docking_capacity: 5,
        services: [:refuel, :market],
        reserves: %{fuel: 2000, food: 1000, ore: 5000}
      },
      %{
        id: "facility-belt-factory",
        name: "Ceres Manufacturing",
        faction_id: "belt-coalition",
        location: "belt-outpost",
        body: "belt",
        type: :factory,
        docking_capacity: 3,
        services: [:market],
        reserves: %{metals: 1000, polymers: 500, components: 200}
      }
    ]
  end

  @doc """
  Returns market configurations per facility. Tuned to create interesting
  trade dynamics: Belt produces ore, Earth produces food, Mars produces fuel.
  """
  @spec markets() :: [map()]
  def markets do
    [
      # Earth — consumer hub, imports raw/refined, exports food/manufactured
      %{
        id: "market-earth-station",
        facility_id: "earth-station",
        prices: %{
          ore: 45.0,
          ice: 30.0,
          gas: 50.0,
          metals: 55.0,
          fuel: 22.0,
          polymers: 50.0,
          water: 10.0,
          components: 90.0,
          electronics: 130.0,
          tools: 100.0,
          food: 8.0,
          medical: 110.0,
          luxury: 160.0
        },
        supply: %{
          ore: 200,
          ice: 100,
          gas: 50,
          metals: 300,
          fuel: 800,
          polymers: 200,
          water: 2000,
          components: 150,
          electronics: 50,
          tools: 100,
          food: 2000,
          medical: 200,
          luxury: 50
        },
        demand: %{
          ore: 15,
          fuel: 15,
          food: 40,
          metals: 10,
          water: 20,
          components: 8,
          medical: 5,
          luxury: 3
        },
        production: %{},
        consumption: %{fuel: 8},
        price_elasticity: 0.02
      },
      # Mars — refining hub, imports ore/ice, exports metals/fuel
      %{
        id: "market-mars-station",
        facility_id: "mars-station",
        prices: %{
          ore: 30.0,
          ice: 15.0,
          gas: 25.0,
          metals: 40.0,
          fuel: 12.0,
          polymers: 45.0,
          water: 15.0,
          components: 95.0,
          electronics: 135.0,
          tools: 95.0,
          food: 35.0,
          medical: 115.0,
          luxury: 170.0
        },
        supply: %{
          ore: 500,
          ice: 300,
          gas: 100,
          metals: 800,
          fuel: 2000,
          polymers: 100,
          water: 500,
          components: 50,
          electronics: 20,
          tools: 80,
          food: 800,
          medical: 50,
          luxury: 20
        },
        demand: %{ore: 20, ice: 10, food: 30, fuel: 15, components: 5},
        production: %{},
        consumption: %{fuel: 10},
        price_elasticity: 0.02
      },
      # Belt — mining/manufacturing, imports food/fuel, exports ore/components
      %{
        id: "market-belt-outpost",
        facility_id: "belt-outpost",
        prices: %{
          ore: 10.0,
          ice: 8.0,
          gas: 12.0,
          metals: 50.0,
          fuel: 30.0,
          polymers: 42.0,
          water: 20.0,
          components: 75.0,
          electronics: 125.0,
          tools: 85.0,
          food: 50.0,
          medical: 120.0,
          luxury: 180.0
        },
        supply: %{
          ore: 3000,
          ice: 500,
          gas: 200,
          metals: 500,
          fuel: 300,
          polymers: 200,
          water: 100,
          components: 300,
          electronics: 100,
          tools: 200,
          food: 400,
          medical: 30,
          luxury: 10
        },
        demand: %{food: 20, fuel: 20, metals: 15, ore: 10},
        production: %{},
        consumption: %{fuel: 15},
        price_elasticity: 0.02
      }
    ]
  end

  @doc """
  Returns ship class definitions with stats.
  """
  @spec ship_classes() :: %{atom() => map()}
  def ship_classes do
    %{
      # fuel_consumption_rate = base * tick_scale() — auto-computed
      courier: %{
        cargo_capacity: 50,
        passenger_capacity: 20,
        fuel_capacity: 80.0,
        fuel_consumption_rate: 0.03 * tick_scale(),
        speed_modifier: 1.5,
        crew_size: 2,
        crew_roles: [:pilot, :general]
      },
      freighter: %{
        cargo_capacity: 500,
        passenger_capacity: 10,
        fuel_capacity: 100.0,
        fuel_consumption_rate: 0.05 * tick_scale(),
        speed_modifier: 1.0,
        crew_size: 5,
        crew_roles: [:pilot, :engineer, :trader, :medic, :general]
      },
      hauler: %{
        cargo_capacity: 2000,
        passenger_capacity: 5,
        fuel_capacity: 200.0,
        fuel_consumption_rate: 0.1 * tick_scale(),
        speed_modifier: 0.6,
        crew_size: 8,
        crew_roles: [:pilot, :pilot, :engineer, :engineer, :trader, :medic, :general, :general]
      },
      tanker: %{
        cargo_capacity: 1500,
        passenger_capacity: 0,
        fuel_capacity: 300.0,
        fuel_consumption_rate: 0.08 * tick_scale(),
        speed_modifier: 0.7,
        crew_size: 6,
        crew_roles: [:pilot, :engineer, :engineer, :trader, :medic, :general]
      },
      miner: %{
        cargo_capacity: 200,
        passenger_capacity: 0,
        fuel_capacity: 120.0,
        fuel_consumption_rate: 0.04 * tick_scale(),
        speed_modifier: 0.8,
        crew_size: 3,
        crew_roles: [:pilot, :engineer, :general]
      }
    }
  end

  @doc """
  Returns ship configurations. Ships start distributed across locations
  with varied classes.
  """
  @spec ships() :: [map()]
  def ships do
    [
      # Terran Authority ships
      ship("Artemis-7", "earth-station", :freighter, 10_000, "terran-authority"),
      ship("Swift Meridian", "earth-station", :courier, 5_000, "terran-authority"),
      ship("Sol Trader", "earth-station", :freighter, 10_000, "terran-authority"),
      # Mars Syndicate ships
      ship("Red Runner", "mars-station", :freighter, 10_000, "mars-syndicate"),
      ship("Dusty Cargo", "mars-station", :tanker, 12_000, "mars-syndicate"),
      # Belt Coalition ships
      ship("Ceres Hauler", "belt-outpost", :hauler, 15_000, "belt-coalition"),
      ship("Ore Express", "belt-outpost", :hauler, 15_000, "belt-coalition"),
      # Independent — freelancer
      ship("Belt Hopper", "belt-outpost", :courier, 5_000, "independent")
    ]
  end

  defp ship(name, location, class, credits, faction_id) do
    id = name |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "-")
    class_stats = Map.get(ship_classes(), class, ship_classes().freighter)

    %{
      id: "ship-#{id}",
      name: name,
      class: class,
      faction_id: faction_id,
      faction_reputation: default_reputation(faction_id),
      location: location,
      universe_offset: {0.0, 0.0},
      credits: credits,
      fuel: class_stats.fuel_capacity,
      fuel_capacity: class_stats.fuel_capacity,
      fuel_consumption_rate: class_stats.fuel_consumption_rate,
      speed_modifier: class_stats.speed_modifier,
      cargo: %{},
      cargo_capacity: class_stats.cargo_capacity,
      known_prices: initial_price_knowledge()
    }
  end

  defp initial_price_knowledge do
    # Ships start with rough knowledge of all markets (slightly inaccurate)
    # Stamped format: %{price: float, tick: 0} — tick 0 = "old memory"
    %{
      "earth-station" => %{
        ore: %{price: 44.0, tick: 0},
        fuel: %{price: 23.0, tick: 0},
        food: %{price: 11.0, tick: 0}
      },
      "mars-station" => %{
        ore: %{price: 36.0, tick: 0},
        fuel: %{price: 19.0, tick: 0},
        food: %{price: 24.0, tick: 0}
      },
      "belt-outpost" => %{
        ore: %{price: 16.0, tick: 0},
        fuel: %{price: 29.0, tick: 0},
        food: %{price: 38.0, tick: 0}
      }
    }
  end

  @doc """
  Returns population configurations per facility.
  """
  @spec populations() :: [map()]
  def populations do
    [
      # Earth — large, well-fed, some workers and merchants
      %{
        id: "pop-earth-workers",
        label: "Earth Station Workers",
        facility_id: "earth-station",
        demographic: :workers,
        population_count: 50_000,
        food_satisfaction: 80,
        total_wealth: 2_000_000,
        consumption: %{food: 30, fuel: 0},
        production_commodity: nil,
        production_amount: 0
      },
      %{
        id: "pop-earth-merchants",
        label: "Earth Station Merchants",
        facility_id: "earth-station",
        demographic: :merchants,
        population_count: 15_000,
        food_satisfaction: 85,
        total_wealth: 3_000_000,
        consumption: %{food: 10, fuel: 0},
        production_commodity: nil,
        production_amount: 0
      },
      # Mars — fuel producers, food-hungry
      %{
        id: "pop-mars-workers",
        label: "Mars Station Workers",
        facility_id: "mars-station",
        demographic: :workers,
        population_count: 30_000,
        food_satisfaction: 55,
        total_wealth: 800_000,
        consumption: %{food: 25, fuel: 0},
        production_commodity: :fuel,
        production_amount: 20
      },
      %{
        id: "pop-mars-scientists",
        label: "Mars Research Team",
        facility_id: "mars-station",
        demographic: :scientists,
        population_count: 5_000,
        food_satisfaction: 60,
        total_wealth: 500_000,
        consumption: %{food: 5, fuel: 0},
        production_commodity: nil,
        production_amount: 0
      },
      # Belt — miners, desperate for food and fuel
      %{
        id: "pop-belt-miners",
        label: "Belt Miners",
        facility_id: "belt-outpost",
        demographic: :workers,
        population_count: 20_000,
        food_satisfaction: 40,
        total_wealth: 400_000,
        consumption: %{food: 15, fuel: 0},
        production_commodity: :ore,
        production_amount: 50
      },
      %{
        id: "pop-belt-merchants",
        label: "Belt Traders",
        facility_id: "belt-outpost",
        demographic: :merchants,
        population_count: 3_000,
        food_satisfaction: 45,
        total_wealth: 600_000,
        consumption: %{food: 5, fuel: 0},
        production_commodity: nil,
        production_amount: 0
      }
    ]
  end

  @doc """
  Returns universe-space offsets for each star system.
  All entity positions within a system are offset by these values
  to place them in unified universe coordinates.
  """
  @spec universe_offsets() :: %{String.t() => {float(), float()}}
  def universe_offsets do
    %{
      "system-sol" => {0.0, 0.0},
      "system-alpha-centauri" => {20.0, 5.0}
    }
  end

  # --- Alpha Centauri System ---

  @doc """
  Returns the Alpha Centauri system bodies configuration.
  """
  @spec alpha_centauri_bodies() :: %{String.t() => Body.t()}
  def alpha_centauri_bodies do
    %{
      "proxima" => %Body{
        id: "proxima",
        name: "Proxima",
        type: :planet,
        orbit_radius: 0.8,
        orbit_period: 300,
        current_angle: 90.0,
        resources: %{ore: 0.6, ice: 0.7, gas: 0.3}
      },
      "haven" => %Body{
        id: "haven",
        name: "Haven",
        type: :planet,
        orbit_radius: 1.8,
        orbit_period: 600,
        current_angle: 200.0,
        resources: %{ice: 0.4, gas: 0.2}
      }
    }
  end

  @doc """
  Returns Alpha Centauri facility configurations.
  """
  @spec ac_facilities() :: [map()]
  def ac_facilities do
    [
      %{
        id: "facility-haven-station",
        name: "Haven Station",
        faction_id: "frontier-ventures",
        location: "haven-station",
        body: "haven",
        type: :station,
        docking_capacity: 6,
        services: [:refuel, :repair, :market],
        reserves: %{fuel: 3000, food: 1500}
      },
      %{
        id: "facility-proxima-outpost",
        name: "Proxima Outpost",
        faction_id: "frontier-ventures",
        location: "proxima-outpost",
        body: "proxima",
        type: :outpost,
        docking_capacity: 4,
        services: [:refuel, :market],
        reserves: %{fuel: 1500, food: 500}
      }
    ]
  end

  @doc """
  Returns Alpha Centauri market configurations.
  """
  @spec ac_markets() :: [map()]
  def ac_markets do
    [
      # Haven — station/hub, imports manufactured, produces food
      %{
        id: "market-haven-station",
        facility_id: "haven-station",
        prices: %{
          ore: 50.0,
          ice: 35.0,
          gas: 55.0,
          metals: 60.0,
          fuel: 20.0,
          polymers: 55.0,
          water: 12.0,
          components: 100.0,
          electronics: 140.0,
          tools: 110.0,
          food: 12.0,
          medical: 120.0,
          luxury: 170.0
        },
        supply: %{
          ore: 150,
          ice: 50,
          gas: 20,
          metals: 100,
          fuel: 1000,
          polymers: 50,
          water: 800,
          components: 30,
          electronics: 10,
          tools: 50,
          food: 1200,
          medical: 40,
          luxury: 10
        },
        demand: %{ore: 20, fuel: 15, food: 30, metals: 5, components: 3},
        production: %{},
        consumption: %{fuel: 8},
        price_elasticity: 0.02
      },
      # Proxima — mining outpost, exports ore, imports everything else
      %{
        id: "market-proxima-outpost",
        facility_id: "proxima-outpost",
        prices: %{
          ore: 12.0,
          ice: 10.0,
          gas: 15.0,
          metals: 55.0,
          fuel: 35.0,
          polymers: 50.0,
          water: 25.0,
          components: 95.0,
          electronics: 135.0,
          tools: 100.0,
          food: 55.0,
          medical: 130.0,
          luxury: 190.0
        },
        supply: %{
          ore: 800,
          ice: 300,
          gas: 100,
          metals: 50,
          fuel: 200,
          polymers: 30,
          water: 50,
          components: 10,
          electronics: 5,
          tools: 20,
          food: 300,
          medical: 10,
          luxury: 5
        },
        demand: %{food: 15, fuel: 25, components: 3},
        production: %{},
        consumption: %{fuel: 10},
        price_elasticity: 0.02
      }
    ]
  end

  @doc """
  Returns Alpha Centauri ship configurations.
  """
  @spec ac_ships() :: [map()]
  def ac_ships do
    [
      ac_ship("Frontier Runner", "haven-station", 5000),
      ac_ship("Proxima Hauler", "proxima-outpost", 5000)
    ]
  end

  defp ac_ship(name, location, credits) do
    id = name |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "-")

    %{
      id: "ship-#{id}",
      name: name,
      system_id: "system-alpha-centauri",
      faction_id: "frontier-ventures",
      faction_reputation: default_reputation("frontier-ventures"),
      location: location,
      universe_offset: {20.0, 5.0},
      credits: credits,
      fuel: 100.0,
      cargo: %{},
      cargo_capacity: 500,
      known_prices: ac_price_knowledge()
    }
  end

  defp ac_price_knowledge do
    %{
      "haven-station" => %{
        ore: %{price: 48.0, tick: 0},
        fuel: %{price: 21.0, tick: 0},
        food: %{price: 13.0, tick: 0},
        metals: %{price: 58.0, tick: 0},
        components: %{price: 98.0, tick: 0},
        tools: %{price: 108.0, tick: 0}
      },
      "proxima-outpost" => %{
        ore: %{price: 13.0, tick: 0},
        fuel: %{price: 34.0, tick: 0},
        food: %{price: 53.0, tick: 0},
        metals: %{price: 53.0, tick: 0},
        components: %{price: 93.0, tick: 0},
        tools: %{price: 98.0, tick: 0}
      }
    }
  end

  @doc """
  Returns Alpha Centauri population configurations.
  """
  @spec ac_populations() :: [map()]
  def ac_populations do
    [
      %{
        id: "pop-haven-colonists",
        label: "Haven Colonists",
        facility_id: "haven-station",
        demographic: :workers,
        population_count: 25_000,
        food_satisfaction: 70,
        total_wealth: 1_000_000,
        consumption: %{food: 20, fuel: 0},
        production_commodity: nil,
        production_amount: 0
      },
      %{
        id: "pop-proxima-miners",
        label: "Proxima Miners",
        facility_id: "proxima-outpost",
        demographic: :workers,
        population_count: 8_000,
        food_satisfaction: 50,
        total_wealth: 300_000,
        consumption: %{food: 10, fuel: 0},
        production_commodity: :ore,
        production_amount: 30
      }
    ]
  end

  @doc """
  ## Tick & World Speed Configuration
  ##
  ## Two independent knobs:
  ##   - ticks_per_second: controls client smoothness (higher = smoother)
  ##   - world_speed: controls simulation pace (lower = slower gameplay)
  ##
  ## Changing ticks_per_second alone does NOT change gameplay speed.
  ## Changing world_speed alone slows/speeds the simulation.
  ## All module constants are computed from tick_scale() and tick_multiplier().

  @doc \"""
  Ticks per second at 1x speed. Controls client update frequency.
  """
  @spec ticks_per_second() :: pos_integer()
  def ticks_per_second, do: 8

  @doc """
  World speed factor. 1.0 = original pace, 0.125 = 8x slower.

  0.125 → Earth↔Mars ~10 min
  0.25 → Earth↔Mars ~5 min
  0.5 → Earth↔Mars ~2.5 min
  1.0 → Earth↔Mars ~1.25 min
  """
  @spec world_speed() :: float()
  def world_speed, do: 0.25

  @doc """
  Milliseconds between ticks at 1x speed.
  """
  @spec tick_interval_ms() :: pos_integer()
  def tick_interval_ms, do: 125

  @doc """
  Per-tick rate multiplier. Multiply base rates by this value.

  Base rates assume 1 tick/sec at 1x world speed. tick_scale adjusts
  for both tick frequency and world speed:
    base_rate * tick_scale = effective per-tick rate

  Current: world_speed / ticks_per_second
  """
  @spec tick_scale() :: float()
  def tick_scale, do: world_speed() / ticks_per_second()

  @doc """
  Interval/duration multiplier. Multiply base intervals by this value.

  A base interval of 5 ticks becomes 5 * tick_multiplier ticks.

  Current: ticks_per_second / world_speed
  """
  @spec tick_multiplier() :: pos_integer()
  def tick_multiplier, do: round(ticks_per_second() / world_speed())

  @first_names ~w(Jara Kael Mira Osei Ren Tova Zeke Lina Dax Yuri Nyx Sol Kira
    Finn Sage Lux Kai Vera Juno Rhea Cass Orion Lyra Thane)
  @last_names ~w(Osei Vance Kowalski Chen Adeyemi Reeves Tanaka Morales
    Ivanova Singh Petrova Nakamura Larsen Okonkwo Reyes)

  @doc """
  Generates a random crew name.
  """
  @spec random_crew_name(atom()) :: String.t()
  def random_crew_name(_role) do
    "#{Enum.random(@first_names)} #{Enum.random(@last_names)}"
  end
end
