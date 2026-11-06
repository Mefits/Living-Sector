"""Bounded fresh-world HTTP smoke; no soak or modification of user saves."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

with tempfile.TemporaryDirectory(prefix="strategy-smoke-") as tmp:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, DATABASE_PATH=str(Path(tmp) / "world.db"),
               DATA_DIR=str(Path("priv/genesis/data").resolve()),
               LIVING_SECTOR_UI_DIR=str(Path("observer").resolve()),
               LIVING_SECTOR_STRATEGY_MODE="execute", BIND_ADDR=f"127.0.0.1:{port}", WORLD_SPEED="1.0")
    with open(Path(tmp) / "server.log", "w+") as log:
        proc = subprocess.Popen([str(Path(sys.argv[1]).resolve())], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 30
            while True:
                if proc.poll() is not None:
                    raise RuntimeError(f"server exited: {proc.returncode}")
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/strategy", timeout=1) as response:
                        state = json.load(response)
                    break
                except (OSError, ValueError):
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.2)
            assert state["schema_version"] == 1, state
            assert state["mode"] == "execute", state
            assert len(state["factions"]) == 2, state
            for faction in state["factions"]:
                assert faction["administrator"] == "logistics"
                assert isinstance(faction["goals"], list)
                assert isinstance(faction["projects"], list)
            print("PASS: migrated fresh Genesis world, two factions, strategy API v1, execute mode")
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read()[-6000:])
            raise
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
