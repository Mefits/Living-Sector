#!/usr/bin/env python3
"""Apply Galaxy 0.6 governance overlays to a fully integrated Galaxy 0.5.

One functional block: policy domain, real Director, engine control,
HTTP validation, and the live Observer-facing command screen.
The parent Galaxy 0.5 remains a draft experiment until its economy/
T2/T3 long-campaign acceptance is independently resolved.
"""
from pathlib import Path
import runpy
repo=Path(__file__).resolve().parents[2]
root=repo/"work/source/Living-Sector-Galaxy-0.2"
if not (root/"crates/sim_core/src/strategy/progression.rs").exists():
    raise RuntimeError("Missing Galaxy05 progression, first apply ci/galaxy05/apply.py")
for module in ("governance_domain.py","director_integration.py",
               "player_http.py","governance_ui.py"):
    runpy.run_path(str(repo/"ci/galaxy06"/module),run_name="__main__")
print("Galaxy 0.6 player science mandates: combined source overlays applied")
