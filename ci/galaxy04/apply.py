"""Apply Galaxy 0.4 Block A to the extracted, separately uploaded source ZIP.

This is an integration overlay: keep the original CI input archive unchanged.
Fail closed if the expected Galaxy 0.3 source layout no longer matches.
"""
from pathlib import Path
import shutil

checkout = Path(__file__).resolve().parents[2]
source = checkout / "work/source/Living-Sector-Galaxy-0.2"
entry = source / "crates/sim_core/src/agents/faction.rs"
module = source / "crates/sim_core/src/agents/faction/relief.rs"
if not entry.is_file():
    raise RuntimeError(f"Missing faction source: {entry}")
text = entry.read_text(encoding="utf-8")

anchor = "pub fn tick_factions(\n"
if text.count(anchor) != 1:
    raise RuntimeError("Cannot find unambiguous faction tick entry point")
text = text.replace(anchor, "mod relief;\n\n" + anchor, 1)

anchor = "    // --- Subsidy posting ---\n"
if text.count(anchor) != 1:
    raise RuntimeError("Cannot find unambiguous accounting/subsidy boundary")
text = text.replace(
    anchor,
    "    // Galaxy 0.4 A: bounded real-credit relief before strategy allocation.\n"
    "    relief::tick_relief(world, events, tick, tick_multiplier);\n\n"
    + anchor,
    1,
)
entry.write_text(text, encoding="utf-8")
module.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(checkout / "ci/galaxy04/relief.rs", module)
print("Applied Galaxy 0.4 A financial-relief module")
# A2: estimate colony buffers using actual household purchase rates.
# The patch remains source-only; it does NOT trigger Windows CI per commit.
import runpy
runpy.run_path(str(checkout / "ci/galaxy04/colony_stock.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/ship_liquidity.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/order_reroute.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/construction_diagnostics.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/trade_run_liquidity.py"), run_name="__main__")
# Galaxy 0.4 B1: new-seed-only geography and pirate home.
runpy.run_path(str(checkout / "ci/galaxy04/worlds08.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/colony_home_priority.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/resource_grade_snapshot.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/galaxy_lanes.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy04/corridors_report.py"), run_name="__main__")
# Galaxy C: DOM-only inspector, no changes to server simulation.
runpy.run_path(str(checkout / "ci/galaxy04/observer_priority.py"), run_name="__main__")
# Galaxy 0.4 D: register the new modular inspector as actual HTTP assets.
runpy.run_path(str(checkout / "ci/galaxy04/runtime_ui_assets.py"), run_name="__main__")
# Galaxy D3: only authoritative eight system lanes, never all-pairs shortcuts.
runpy.run_path(str(checkout / "ci/galaxy04/no_interstellar_mesh.py"), run_name="__main__")
# D4: strategy can plan over connected corridors; ships still move leg by leg.
runpy.run_path(str(checkout / "ci/galaxy04/strategy_multihop.py"), run_name="__main__")
# D5: physical transit cannot silently jump over absent graph edges.
runpy.run_path(str(checkout / "ci/galaxy04/no_phantom_ship_travel.py"), run_name="__main__")
# D6: only adjust legacy TEST fixtures to register their graph vertices.
runpy.run_path(str(checkout / "ci/galaxy04/register_test_locations.py"), run_name="__main__")
# Galaxy 0.4.1: ONE combined economic fix from all 3 playtest snapshots.
runpy.run_path(str(checkout / "ci/galaxy041/unified.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy041/colony_aftercare.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy041/native_regressions.py"), run_name="__main__")
runpy.run_path(str(checkout / "ci/galaxy041/expansion_gate.py"), run_name="__main__")
