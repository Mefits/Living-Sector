#!/usr/bin/env python3
"""Apply a major native player ECONOMIC mandate block to Galaxy 0.6.

Requires Galaxy 0.4.1, Galaxy 0.5, Galaxy 0.6 applied first. No
merging with stable/main and no uncontrolled changes to seed worlds.
"""
from pathlib import Path
import runpy
repo=Path(__file__).resolve().parents[2]
root=repo/"work/source/Living-Sector-Galaxy-0.2"
if not (root/"crates/sim_core/src/strategy/governance.rs").is_file():
    raise RuntimeError("Galaxy 0.6 governance must be applied before 0.6.1")
for p in ("domain.py","native_goals.py","server_api.py","economy_ui.py","status.py"):
    runpy.run_path(str(repo/"ci/galaxy061"/p),run_name="__main__")
print("Galaxy 0.6.1 one integrated player economic-mandate block")
