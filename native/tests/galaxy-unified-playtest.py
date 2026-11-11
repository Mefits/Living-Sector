#!/usr/bin/env python3
"""One bounded LIVE Galaxy playtest for the combined 0.6.3-0.6.7 branch.

Real native server, 8 world JSON systems and 3 factions; real HTTP governance.
No simulated finance, fake event stream, balance replay or user saved files.
"""
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def check(value, message):
    if not value:
        raise AssertionError(message)


def request(base, path, method="GET", body=None, raw=False):
    data=json.dumps(body).encode("utf-8") if body is not None else None
    req=urllib.request.Request(base+path,data=data,method=method,
        headers={"Content-Type":"application/json"} if data is not None else {})
    with urllib.request.urlopen(req,timeout=4) as response:
        if raw:
            return response.status,response.read().decode("utf-8"),response.headers
        return response.status,json.load(response),response.headers


def wait_until(label, fn, proc, seconds=35):
    end=time.monotonic()+seconds
    last=None
    while time.monotonic()<end:
        if proc.poll() is not None:
            raise RuntimeError("Server exited before "+label+": "+str(proc.returncode))
        try:
            value=fn()
            if value:
                return value
        except (OSError,ValueError,KeyError,urllib.error.URLError) as exc:
            last=str(exc)
        time.sleep(0.2)
    raise TimeoutError(label+" never became observable: "+str(last))


def main():
    binary=Path(sys.argv[1]).resolve()
    report_path=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else None
    checks=[]
    summary={"status":"failed","checks":checks,"world":"galaxy-8-systems",
             "schema":"strategy-v1","runtime_mode":"execute"}
    with tempfile.TemporaryDirectory(prefix="living-sector-unified-galaxy-") as temp:
        db=Path(temp)/"world.db"
        with socket.socket() as sock:
            sock.bind(("127.0.0.1",0))
            port=sock.getsockname()[1]
        base=f"http://127.0.0.1:{port}"
        env=dict(os.environ, BIND_ADDR=f"127.0.0.1:{port}",
            DATABASE_PATH=str(db),
            DATA_DIR=str(Path("priv/galaxy/data").resolve()),
            LIVING_SECTOR_UI_DIR=str(Path("observer").resolve()),
            LIVING_SECTOR_GALAXY="1",
            LIVING_SECTOR_STRATEGY_MODE="execute",
            WORLD_SPEED="1",
            RUST_LOG="sim_server=warn,sim_core=warn")
        # Baseline director: keep HTN opt-in outside this single integration gate.
        env.pop("LIVING_SECTOR_PLANNER",None)
        proc=None
        error=None
        with (Path(temp)/"server.log").open("w+",encoding="utf-8") as log:
            try:
                check(binary.is_file(),"Missing native server")
                proc=subprocess.Popen([str(binary)],env=env,
                    stdout=log,stderr=subprocess.STDOUT)
                start=wait_until("native Galaxy boot",
                    lambda: request(base,"/api/strategy")[1]
                        if request(base,"/api/strategy")[1].get("commanders")
                        else None,proc,seconds=45)
                check(start["schema_version"]==1,"unexpected strategy schema")
                check(start["mode"]=="execute","strategy not executing")
                check(isinstance(start.get("production_objectives"),dict),
                      "persistent objective field missing from combined API")
                checks.append("fresh eight-system Galaxy starts with direct-source native server")
                _,world,_=request(base,"/api/report")
                _,health,_=request(base,"/api/health")
                expected={"terran-authority","pirates","ceti-freeholds"}
                factions={f["faction_id"] for f in start["factions"]}
                check(factions==expected,("wrong faction roster",factions))
                check(set(start["commanders"])==expected,"native Director roster differs")
                check(len(world.get("systems",[]))==8,
                    ("wrong Galaxy system count",len(world.get("systems",[]))))
                summary.update(initial_tick=health["tick"],systems=8,
                    factions=sorted(factions))
                checks.append("eight real systems and three distinct faction heads")
                # UI and separate JS ES modules must be served by the unified
                # *native Rust server*, not only pass standalone Node tests.
                pages=(
                    ("/observer/",None),
                    ("/observer/governance-economy.html","Долгосрочная цель Главы"),
                    ("/observer/governance-approvals.html","Доказанный эффект поручения"),
                    ("/observer/governance-charter.html",None),
                    ("/observer/app.js","map-primitives.js"),
                    ("/observer/map-primitives.js","export function"),
                    ("/observer/transport.js","export async function getJSON"),
                )
                for path,fragment in pages:
                    code,body,headers=request(base,path,raw=True)
                    check(code==200 and (fragment is None or fragment in body),
                        "Native Observer asset missing/invalid: "+path)
                    if path.endswith(".js"):
                        check("javascript" in headers.get("Content-Type",""),
                            "Incorrect native JS MIME: "+path)
                checks.append("all actual Observer R1/R2 and faction governance HTTP assets")
                # The head is asked to make a real decision, while a player's
                # HOLD economy mandate must remain non-spending. The 202 reply
                # alone is NOT proof it reached the simulation.
                code,speed,_=request(base,"/api/sim/speed","POST",
                    {"ticks_per_second":30,"world_speed":1})
                check(code==200,"cannot set bounded game tick rate")
                code,queued,_=request(base,"/api/player/economic-mandate","POST",{
                    "faction_id":"terran-authority",
                    "location":"earth-station","commodity":"water","kind":"supply",
                    "min_stock":1200,"mode":"hold",
                    "budget_ceiling_cr":30000,"treasury_floor_cr":10000
                })
                check(code==202 and queued.get("status")=="queued",
                      "economic HOLD command not queued")
                applied=wait_until("native faction applied player HOLD command",
                    lambda: (s if s.get("economic_mandates",{})
                        .get("terran-authority",{}).get("mode")=="hold"
                        else None) if (s:=request(base,"/api/strategy")[1]) else None,
                    proc,seconds=35)
                mandate=applied["economic_mandates"]["terran-authority"]
                check(mandate["spent_cr"]==0,
                      "hold immediately charged its own mandate")
                checks.append("player HOLD command observed in real Director, zero mandate debit")
                # Wait just for ONE actual head evaluation cycle, not for
                # years of production or a fabricated construction success.
                evaluated=wait_until("one native head and policy decision",
                    lambda: (s if (
                        s.get("snapshot_tick",0)>start.get("snapshot_tick",0)
                        and any(f.get("head") for f in s["factions"])
                        and (lambda h:any(p.get("department")=="economy"
                            and p.get("status")=="hold" for p in
                            (h or {}).get("policy_impacts",[])))
                           (next((f.get("head") for f in s["factions"]
                             if f["faction_id"]=="terran-authority"),None))
                        ) else None)
                        if (s:=request(base,"/api/strategy")[1]) else None,
                    proc,seconds=40)
                head=next(f["head"] for f in evaluated["factions"]
                    if f["faction_id"]=="terran-authority")
                impact=next(p for p in head["policy_impacts"]
                    if p["department"]=="economy")
                check(impact["status"]=="hold" and not impact["selected"],
                    "HOLD became an authorized native order")
                check(isinstance(head.get("goal_reviews"),list),
                    "head decision portfolio missing")
                for faction in evaluated["factions"]:
                    construction=faction.get("construction") or {}
                    chain=construction.get("execution_chain")
                    if chain is not None:
                        check(len(chain.get("steps",[]))==5 and
                            chain.get("next_stage") in
                            {"commission","materials","labor","inputs",
                             "first_output","complete"},
                            "native production chain schema invalid")
                checks.append("one real head decision with policy audit and production schema")
                summary["end_tick"]=evaluated["snapshot_tick"]
                summary["head_choice"]=head.get("selected_option")
                summary["policy_impact"]=impact["status"]
                summary["production_objectives"]=len(
                    evaluated.get("production_objectives",{}))
                summary["visible_project_count"]=sum(
                    len(f.get("projects",[])) for f in evaluated["factions"])
                summary["status"]="passed"
            except BaseException as exc:
                error=exc
                summary["error"]=repr(exc)
            finally:
                if proc is not None and proc.poll() is None:
                    proc.terminate()
                    try:proc.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        proc.kill();proc.wait(timeout=5)
                if db.exists():
                    try:
                        with sqlite3.connect(f"file:{db}?mode=ro",uri=True) as con:
                            summary["sqlite_integrity"]=con.execute(
                                "PRAGMA integrity_check").fetchone()[0]
                    except sqlite3.Error as exc:
                        summary["sqlite_integrity"]=repr(exc)
                log.flush()
                if error:
                    log.seek(0)
                    print(log.read()[-8000:],file=sys.stderr)
        if report_path:
            report_path.parent.mkdir(parents=True,exist_ok=True)
            report_path.write_text(json.dumps(summary,ensure_ascii=False,
                indent=2)+"\n",encoding="utf-8")
        print(json.dumps(summary,ensure_ascii=False,indent=2))
        if error:raise error
        check(summary.get("sqlite_integrity")=="ok",
            "Galaxy SQLite integrity check failed")
    return 0


if __name__=="__main__":
    sys.exit(main())
