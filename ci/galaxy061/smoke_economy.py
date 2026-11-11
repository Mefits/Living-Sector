#!/usr/bin/env python3
"""One LIVE Windows test of the actual economic-mandate command path.

The acceptance focuses on native command queue, owned station checks,
persisted state, mode/budget changes and avoiding fake success.
The whole 1000-year technology campaign is not this test.
"""
from __future__ import annotations
import json,os,subprocess,tempfile,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/"work/source/Living-Sector-Galaxy-0.2"
EXE=SOURCE/"target/release/genesis_server.exe"
OUT=ROOT/"economic-mandate-smoke-results"
OUT.mkdir(exist_ok=True)
BASE="http://127.0.0.1:18107"

def http(path,method="GET",data=None,headers=None):
    payload=json.dumps(data).encode() if data is not None else None
    h=dict(headers or {})
    if payload is not None:h["Content-Type"]="application/json"
    req=urllib.request.Request(BASE+path,data=payload,headers=h,method=method)
    with urllib.request.urlopen(req,timeout=10) as r:
        return r.status,json.load(r)

def wait(predicate,seconds=65):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if process.poll() is not None:raise RuntimeError(f"Server exited {process.returncode}")
        try:
            observed=predicate()
            if observed:return observed
        except (urllib.error.URLError,TimeoutError,ValueError):pass
        time.sleep(.5)
    raise TimeoutError("Native goal/response not visible after real game ticks")

logdata={"status":"not_run","checks":[]}
def check(label,assertion):
    if not assertion:raise AssertionError(label)
    logdata["checks"].append(label)

with tempfile.TemporaryDirectory(prefix="galaxy061-smoke-") as folder:
    env=os.environ.copy()
    env.update({
        "BIND_ADDR":"127.0.0.1:18107",
        "DATABASE_PATH":str(Path(folder)/"world.db"),
        "DATA_DIR":str(SOURCE/"priv/galaxy/data"),
        "LIVING_SECTOR_UI_DIR":str(SOURCE/"observer"),
        "LIVING_SECTOR_GALAXY":"1",
        "LIVING_SECTOR_STRATEGY_MODE":"execute",
        "LIVING_SECTOR_PLANNER":"hybrid",
        "LIVING_SECTOR_PLANNER_SHADOW":"0",
        "LIVING_SECTOR_PLANNER_COMPARE":"0",
        "WORLD_SPEED":"16",
        "RUST_LOG":"sim_server=info,sim_core=warn",
    })
    with (OUT/"native-server.log").open("wb") as console:
        process=subprocess.Popen([str(EXE)],cwd=SOURCE,
            env=env,stdout=console,stderr=subprocess.STDOUT)
        try:
            initial=wait(lambda: (s if s.get("commanders") else None)
                if (s:=http("/api/strategy")[1]) else None,90)
            check("three real directors",len(initial["commanders"])==3)
            check("fresh save has no economic policy",not initial.get("economic_mandates"))
            report=http("/api/report")[1]
            stations=sorted([
                f for f in report["facilities"]
                if f.get("type")=="station" and f.get("faction_id") in initial["commanders"]
            ],key=lambda f:(f.get("faction_id",""),f.get("location","")))
            check("real owned stations exist",bool(stations))
            station=stations[0]
            faction=station["faction_id"]
            location=station["location"]
            webpage=urllib.request.urlopen(BASE+"/observer/governance-economy.html",timeout=6).read()
            check("live economy governance UI served",
                b"/api/player/economic-mandate" in webpage)
            stock_before=float(next((m.get("supply",{}).get("water",0)
                    for m in report["markets"] if m.get("facility_location")==location),0))
            def submit(mode,budget=30000):
                body={"faction_id":faction,"location":location,
                    "commodity":"water","kind":"supply","min_stock":500,
                    "mode":mode,"budget_ceiling_cr":budget,"treasury_floor_cr":10000}
                code,reply=http("/api/player/economic-mandate","POST",body)
                check("HTTP queued, not asserted success: "+mode,
                    code==202 and reply.get("status")=="queued")
                return wait(lambda: (m if m and m.get("mode")==mode else None)
                    if (m:=http("/api/strategy")[1].get("economic_mandates",{}).get(faction)) else None)
            active=submit("delegated")
            check("native faction and station binding",
                active["location"]==location and active["commodity"]=="water")
            check("directive cannot immediately conjure credits",
                0<=active["spent_cr"]<=active["budget_ceiling_cr"])
            other=http("/api/strategy")[1]["economic_mandates"]
            check("no other faction captured",set(other)=={faction})
            held=submit("hold")
            check("switch to hold preserved real obligations",held["spent_cr"]>=active["spent_cr"])
            advised=submit("advise")
            check("switch to advice preserves spending",advised["spent_cr"]>=active["spent_cr"])
            # Invalid station belongs to no faction. HTTP may enqueue but
            # only game thread can reject after seeing the real ECS world.
            code,resp=http("/api/player/economic-mandate","POST",{
                "faction_id":faction,"location":"invented-sector-home",
                "commodity":"water","kind":"supply","min_stock":100,
                "mode":"delegated","budget_ceiling_cr":30000,
                "treasury_floor_cr":10000})
            check("invalid station request only queued until ECS validation",
                code==202 and resp["status"]=="queued")
            time.sleep(1.5)
            saved=http("/api/strategy")[1]["economic_mandates"][faction]
            check("invalid foreign or missing station never applied",
                saved["location"]==location)
            invalid={"faction_id":faction,"location":location,
                "commodity":"ore","kind":"supply","min_stock":300,
                "mode":"delegated","budget_ceiling_cr":30000,"treasury_floor_cr":10000}
            try:
                http("/api/player/economic-mandate","POST",invalid)
                raise AssertionError("Unknown mandate commodity wrongly accepted")
            except urllib.error.HTTPError as e:
                check("invalid supply commodity rejected HTTP 400",e.code==400)
            try:
                http("/api/player/economic-mandate","POST",{
                    "faction_id":faction,"location":location,
                    "commodity":"water","kind":"supply","min_stock":300,
                    "mode":"delegated","budget_ceiling_cr":30000,"treasury_floor_cr":10000},
                    headers={"Origin":"http://untrusted.example"})
                raise AssertionError("Cross-origin mutation wrongly accepted")
            except urllib.error.HTTPError as e:
                check("cross-origin control denied HTTP 403",e.code==403)
            code,reply=http("/api/player/economic-mandate/"+faction,"DELETE")
            check("cancel merely queued",code==202 and reply["status"]=="queued")
            wait(lambda:faction not in http("/api/strategy")[1].get("economic_mandates",{}))
            check("cleared the player mandate without deleting native faction",
                faction in http("/api/strategy")[1]["commanders"])
            report_after=http("/api/report")[1]
            stock_after=float(next((m.get("supply",{}).get("water",0)
                    for m in report_after["markets"] if m.get("facility_location")==location),0))
            # Diff may reflect *native* background consumption/production,
            # NOT proof that pressing a button delivered anything.
            logdata.update(status="passed",faction_id=faction,location=location,
                water_before=stock_before,water_after=stock_after,
                note="Response 202 is a queue receipt; physical delivery is a separate observation")
        except BaseException as exc:
            logdata.update(status="failed",error=repr(exc))
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=14)
                except subprocess.TimeoutExpired:
                    process.kill();process.wait(timeout=5)
            (OUT/"economic-mandate-smoke.json").write_text(
                json.dumps(logdata,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
            print(json.dumps(logdata,indent=2,ensure_ascii=False),flush=True)
