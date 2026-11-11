#!/usr/bin/env python3
"""One reproducible Galaxy 0.6.2 overlay after 0.6.1. No changes to main."""
from pathlib import Path
import runpy

repo=Path(__file__).resolve().parents[2]
root=repo/"work/source/Living-Sector-Galaxy-0.2"
if not (root/"crates/sim_core/src/strategy/economic_mandate.rs").is_file():
    raise RuntimeError("Galaxy 0.6.1 must be applied before 0.6.2")
for name in ("charter.py","integration.py","api_ui.py","status.py"):
    runpy.run_path(str(repo/"ci/galaxy062"/name),run_name="__main__")
print("Galaxy 0.6.2 charter — single coherent native governance block")
