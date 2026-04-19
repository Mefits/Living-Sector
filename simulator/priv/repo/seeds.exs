# Seed the simulation world from JSON data files.
#
# Run with: mix run priv/repo/seeds.exs
# Or via:   mix ecto.setup (includes create + migrate + seed)
#
# Safe to re-run — uses upsert (insert or update) on all records.
# Add new systems by creating priv/data/worlds/new_system.json
# and re-running this script.

Simulator.Seed.seed_all()
