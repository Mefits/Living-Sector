#!/usr/bin/env python3
"""Apply Galaxy 0.6.3 after Galaxy 0.6.2, once, on archived Genesis sources."""
from pathlib import Path
import runpy

repo=Path(__file__).resolve().parents[2]
root=repo/"work/source/Living-Sector-Galaxy-0.2"
if not (root/"crates/sim_core/src/strategy/charter.rs").is_file():
    raise RuntimeError("Galaxy 0.6.2 charter must be applied before 0.6.3")
for name in ("proposals.py","native_integration.py","api_ui.py","native_fixture_tests.py"):
    runpy.run_path(str(repo/"ci/galaxy063"/name),run_name="__main__")
print("Galaxy 0.6.3: proposals, exact native action gate, engine queue, UI, regression")
