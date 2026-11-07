"""Bounded station-admin API/native production integration check."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

with tempfile.TemporaryDirectory(prefix="workforce-smoke-") as tmp:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, DATABASE_PATH=str(Path(tmp) / "world.db"),
               DATA_DIR=str(Path("priv/genesis/data").resolve()),
               LIVING_SECTOR_STRATEGY_MODE="execute", BIND_ADDR=f"127.0.0.1:{port}", WORLD_SPEED="1.0")
    with open(Path(tmp) / "server.log", "w+") as log:
        proc = subprocess.Popen([str(Path(sys.argv[1]).resolve())], env=env, stdout=log, stderr=log)
        def get(path):
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/{path}", timeout=1) as response:
                return json.load(response)
        try:
            deadline = time.monotonic() + 35
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise RuntimeError(f"server exited: {proc.returncode}")
                try:
                    people = get("populations")["data"]
                    facilities = get("facilities")["data"]
                    state = get("strategy")
                    paid = [f for f in facilities if (f.get("crew") or {}).get("work_shift")]
                    factions = {f["faction_id"] for f in paid}
                    if {"terran-authority", "pirates"}.issubset(factions):
                        stations = state["stations"]
                        assert stations and all(s["executing"] for s in stations)
                        assert {"terran-authority", "pirates"}.issubset({s["faction_id"] for s in stations})
                        assert all(s["assigned_workers"] + s["already_working"] <= s["workforce"] for s in stations)
                        assert any(m["actual_workers"] > 0 for s in stations for m in s["modules"])
                        expected = sum(len(json.loads(path.read_text()).get("populations", [])) for path in Path("priv/genesis/data/worlds").glob("*.json"))
                        assert len(people) == expected, (len(people), expected)
                        assert all(p["total_wealth"] >= 0 for p in people)
                        assert all(f["crew"]["work_shift"]["wages"] > 0 for f in paid)
                        print(f"PASS: tick={state['snapshot_tick']}, populations={len(people)}, paid_workplaces={len(paid)}, both factions use station administration and native payroll")
                        break
                    assert state["snapshot_tick"] <= 160, "bounded checkpoint exceeded"
                except (OSError, ValueError):
                    pass
                time.sleep(0.2)
            else:
                raise AssertionError("No paid work in both factions within 35 seconds")
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read()[-4000:])
            raise
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
