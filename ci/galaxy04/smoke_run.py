#!/usr/bin/env python3
"""One bounded Galaxy 0.4 D smoke test on real compiled Windows server.

Exercises fresh SQLite seed, eight-system world, native travel graph,
pirate relocation, Observer HTTP assets, real ticking, strategy endpoint
and engine persistence. No fabricated economy success claims.
Requires: Python 3.12+, compiled genesis_server.exe, original seed data.

Run: python ci/galaxy04/smoke_run.py
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

REPO = Path(__file__).resolve().parents[2]
PROJECT = REPO / "work/source/Living-Sector-Galaxy-0.2"
EXE = PROJECT / "target/release/genesis_server.exe"
OUT = REPO / "smoke-results"
BASE = "http://127.0.0.1:18094"
OUT.mkdir(exist_ok=True)

def get(path: str, timeout: float = 3) -> tuple[bytes, str]:
    with urllib.request.urlopen(BASE + path, timeout=timeout) as result:
        assert result.status == 200, (path, result.status)
        return result.read(), result.headers.get_content_type()

def doc(path: str) -> dict:
    data, kind = get(path, timeout=6)
    assert kind == "application/json", (path,kind)
    return json.loads(data)

def until(predicate, max_seconds, why):
    end = time.monotonic() + max_seconds
    last = ""
    while time.monotonic() < end:
        if process.poll() is not None:
            raise RuntimeError(f"Server exited {process.returncode} while {why}")
        try:
            value = predicate()
            if value:
                return value
        except (urllib.error.URLError, TimeoutError, ConnectionError, ValueError,
                json.JSONDecodeError, AssertionError) as e:
            last = str(e)
        time.sleep(0.8)
    raise TimeoutError(f"{why} not ready in {max_seconds}s; last response {last}")

result = {"result": "incomplete", "checks": [], "warning":
          "Short runtime sanity test only; no 10k-tick economic guarantee"}
def checked(label, condition, details=None):
    if not condition:
        raise AssertionError(f"{label}: {details}")
    result["checks"].append(label)

with tempfile.TemporaryDirectory(prefix="living-sector-galaxy04d-") as temp:
    td=Path(temp)
    env=os.environ.copy()
    env.update({
        "DATA_DIR":str(PROJECT/"priv/galaxy/data"),
        "DATABASE_PATH":str(td/"smoke04.db"),
        "LIVING_SECTOR_UI_DIR":str(PROJECT/"observer"),
        "LIVING_SECTOR_GALAXY":"1",
        "LIVING_SECTOR_STRATEGY_MODE":"execute",
        "LIVING_SECTOR_PLANNER":"hybrid",
        "LIVING_SECTOR_PLANNER_SHADOW":"0",
        "LIVING_SECTOR_PLANNER_COMPARE":"0",
        "BIND_ADDR":"127.0.0.1:18094",
        "WORLD_SPEED":"16",
        "RUST_LOG":"sim_core=warn,sim_db=info,sim_server=info",
    })
    with (OUT/"genesis_server.log").open("wb") as log:
        process = subprocess.Popen([str(EXE)], cwd=PROJECT, env=env,
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            health = until(lambda:doc("/api/health"), 90,
                           "fresh SQLite seed and HTTP server")
            checked("live HTTP health",health.get("status")=="ok" and
                    health.get("running") is True)
            checked("world speed x16",abs(float(health.get("world_speed",0))-16)<.01)

            report=until(lambda: (r if len(r.get("systems",[]))==8
                                  and r.get("facilities") else None)
                         if (r:=doc("/api/report")) else None,
                         45,"eight-system live report")
            names={s["name"] for s in report["systems"]}
            checked("eight distinct star systems",len(names)==8 and {
                "Sol","Alpha Centauri","Nadir","Epsilon Eridani"
            }<=names,sorted(names))
            checked("all three factions in new world",{
                "genesis","ceti","pirates"
            }<=set(str(f.get("id","")) for f in report.get("factions",[])) or
                len(report.get("factions",[]))==3, report.get("factions",[]))
            pirate=[f for f in report["facilities"] if f.get("faction_id")=="pirates"]
            checked("pirate facilities migrated",len(pirate)>=5 and all(
                f.get("body_id")=="nadir-wreckhold" for f in pirate),
                [(f.get("id"),f.get("body_id")) for f in pirate])
            checked("pirate fleet present",len([
                x for x in report.get("ships",[]) if x.get("faction_id")=="pirates"
            ])>=8)
            checked("economy seeded",len(report.get("markets",[]))>=3 and
                    len(report.get("populations",[]))>=3)
            links=report.get("system_links",[])
            expected_lanes={
                frozenset(("Sol","Alpha Centauri")),
                frozenset(("Sol","Epsilon Eridani")),
                frozenset(("Alpha Centauri","Tau Ceti")),
                frozenset(("Epsilon Eridani","Tau Ceti")),
                frozenset(("Tau Ceti","Vega")),
                frozenset(("Vega","Lalande")),
                frozenset(("Tau Ceti","Barnard's Star")),
                frozenset(("Barnard's Star","Nadir")),
            }
            actual_lanes={frozenset((e.get("a"),e.get("b"))) for e in links}
            checked("EXACTLY eight true interstellar corridors (no complete mesh)",
                    isinstance(links,list) and len(links)==8 and
                    actual_lanes==expected_lanes,
                    {"expected":[sorted(a) for a in expected_lanes],
                     "actual":links})
            for e in links:
                checked("corridor endpoints correspond to real systems",
                        e.get("a") in names and e.get("b") in names
                        and e.get("a")!=e.get("b"),e)
            all_bodies=[b for sys in report["systems"] for b in sys.get("bodies",[])]
            graded=[b for b in all_bodies if b.get("resource_grades")]
            checked("published static planet ore/ice/gas tiers",len(graded)>0 and
                    all(1<=g<=5 for b in graded for g in b["resource_grades"].values()))

            html,kind=get("/observer/native.html")
            checked("native Observer HTML",b"inspector-body" in html and
                    b"/observer/priority-inspector.css" in html)
            js,kind=get("/observer/priority-inspector.js")
            checked("priority JS served, not 404",kind in (
                "text/javascript","application/javascript") and
                    b"renderPriorityInspector" in js)
            css,kind=get("/observer/priority-inspector.css")
            checked("priority CSS served, not 404",
                    kind=="text/css" and b"priority-faction" in css)
            app,kind=get("/observer/app.js")
            checked("Observer actually imports priority JS",
                    b'renderPriorityInspector' in app)
            # Native strategy and colonies are real API snapshots,
            # independent of the presentation's claims.
            strategy=doc("/api/strategy")
            checked("strategy API responds",isinstance(strategy,dict))

            advanced=until(lambda: (h if int(h.get("tick",0)) >= 240 else None)
                           if (h:=doc("/api/health")) else None,
                           85,"240 live simulation ticks")
            checked("real tick progression >=240",int(advanced["tick"])>=240)
            later=doc("/api/report")
            checked("world stayed coherent after ticks",
                    len(later.get("systems",[]))==8 and
                    len(later.get("facilities",[]))>=len(pirate))
            checked("first-run SQLite database created",
                    (td/"smoke04.db").is_file())
            result.update(result="passed",
                          tick=int(later.get("tick",0)),
                          systems=sorted(names),corridors=len(links),
                          pirate_facilities=len(pirate),
                          ships=len(later.get("ships",[])),
                          markets=len(later.get("markets",[])),
                          checked_at_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()))
        except BaseException as error:
            result.update(result="failed", error=str(error))
            print("SMOKE FAILURE: "+str(error),flush=True)
            raise
        finally:
            try:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
            finally:
                (OUT/"galaxy04-d-smoke.json").write_text(
                    json.dumps(result,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
                print(json.dumps(result,indent=2,ensure_ascii=False),flush=True)
                if result["result"]!="passed":
                    log.flush()
                    try:
                        tail=(OUT/"genesis_server.log").read_text(
                            encoding="utf8",errors="replace")[-9000:]
                        print("SERVER LOG (tail):\n"+tail,file=sys.stderr,flush=True)
                    except OSError:pass
