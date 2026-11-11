#!/usr/bin/env python3
"""Apply major Galaxy 0.5 block E on top of the already applied Galaxy 0.4.1.

Use exactly once, after python ci/galaxy04/apply.py, on a clean extracted
source archive. The full Windows workflow will be connected only after E2–E8
are complete. E1 currently introduces a tested-by-design pure tier module;
it deliberately does not modify economy, stations, or technologies.
"""
import runpy
from pathlib import Path

checkout=Path(__file__).resolve().parents[2]
base=checkout/"work/source/Living-Sector-Galaxy-0.2"
if not (base/"Cargo.toml").is_file():
    raise RuntimeError("Expected extracted Galaxy 0.4.1 source archive")
runpy.run_path(str(checkout/"ci/galaxy05/tier_domain.py"),run_name="__main__")
# One larger integrated overlay, built/tested as a whole only once.
for step in (
    "native_tier2_tier3.py",
    "station_state.py",
    "station_native_exec.py",
    "station_slot_limit.py",
    "industry_goals.py",
    "station_observer.py",
):
    runpy.run_path(str(checkout/"ci/galaxy05"/step),run_name="__main__")
print("Galaxy 0.5 E1-E7 core native tier/commodity/research/industry/upgrade overlays applied")
