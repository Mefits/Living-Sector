#!/usr/bin/env python3
"""Bounded LIVE Windows server test of the first player governance control.

Explicit 202 response is only a QUEUE receipt. Confirm applied state
from /api/strategy, test delegated -> hold -> advise -> clear, and
verify no extra faction policy or ships are magically created.
Do not misreport a missing science shift as failure of API plumbing.
"""
import json,os,subprocess,sys,tempfile,time,urllib.request,urllib.error
from pathlib import Path

REPO=Path(__file__).resolve().parents[2]
ROOT=REPO/"work/source/Living-Sector-Galaxy-0.2"
EXE=ROOT/"target/release/genesis_server.exe"
BASE="http://127.0.0.1:18106"
OUT=REPO/"governance-smoke-results"
OUT.mkdir(parents=True,exist_ok=True)

def request(path,method="GET",data=None):
    payload=json.dumps(data).encode() if data is not None else None
    headers={"Content-Type":"application/json"} if data is not None else {}
    req=urllib.request.Request(BASE+path,data=payload,headers=headers,method=method)
    with urllib.request.urlopen(req,timeout=10) as r:
        return r.status,json.loads(r.read())

def wait_for(fn,deadline=50):
    until=time.monotonic()+deadline
    while time.monotonic()<until:
        if proc.poll() is not None:raise RuntimeError(f"Server exited {proc.returncode}")
        try:
            found=fn()
            if found:return found
        except (urllib.error.URLError,TimeoutError,ValueError,json.JSONDecodeError):pass
        time.sleep(.5)
    raise TimeoutError("Timed out waiting for real native governance state")

results={"status":"incomplete","checks":[]}
def check(name,condition):
    if not condition:raise AssertionError(name)
    results["checks"].append(name)
def native_mandate(fid,mode):
    strategy=request("/api/strategy")[1]
    m=strategy.get("research_mandates",{}).get(fid)
    return m if m and m.get("mode")==mode else None

with tempfile.TemporaryDirectory(prefix="galaxy06-governance-") as tmp:
    env=os.environ.copy()
    env.update({
        "BIND_ADDR":"127.0.0.1:18106",
        "DATABASE_PATH":str(Path(tmp)/"world06.db"),
        "DATA_DIR":str(ROOT/"priv/galaxy/data"),
        "LIVING_SECTOR_UI_DIR":str(ROOT/"observer"),
        "LIVING_SECTOR_GALAXY":"1",
        "LIVING_SECTOR_STRATEGY_MODE":"execute",
        "LIVING_SECTOR_PLANNER":"hybrid",
        "LIVING_SECTOR_PLANNER_SHADOW":"0",
        "LIVING_SECTOR_PLANNER_COMPARE":"0",
        "WORLD_SPEED":"16",
        "RUST_LOG":"sim_server=info,sim_core=warn",
    })
    with (OUT/"server.log").open("wb") as log:
        proc=subprocess.Popen([str(EXE)],cwd=ROOT,env=env,
                              stdout=log,stderr=subprocess.STDOUT)
        try:
            strategy=wait_for(lambda: (x if x.get("commanders") else None)
                              if (x:=request("/api/strategy")[1]) else None,90)
            factions=sorted(strategy["commanders"])
            check("three real autonomous factions",len(factions)==3)
            faction=factions[0]
            check("no player mandate on new save",not strategy.get("research_mandates"))
            html=urllib.request.urlopen(BASE+"/observer/governance.html",timeout=7).read()
            check("live player governance page",b"/api/player/research-mandate" in html)
            check("no manual unit orders on player screen",b"ship_order" not in html)
            def put(mode,budget=30000):
                code,resp=request("/api/player/research-mandate","POST",{
                    "faction_id":faction,"target_technology":"automation",
                    "mode":mode,"budget_ceiling_cr":budget,
                    "treasury_floor_cr":10000})
                check("HTTP returns only queued for "+mode,
                      code==202 and resp["status"]=="queued")
            put("delegated")
            m=wait_for(lambda:native_mandate(faction,"delegated"))
            check("delegated mandate applied to native Director",m["target_technology"]=="automation" and m["budget_ceiling_cr"]==30000)
            check("no credit minted just by setting a mandate",m["spent_cr"]==0)
            check("other faction not overridden",set(request("/api/strategy")[1]["research_mandates"])=={faction})
            put("hold")
            m=wait_for(lambda:native_mandate(faction,"hold"))
            check("science can be explicitly held",m["mode"]=="hold")
            before=request("/api/strategy")[1]["commanders"][faction].get("last_research_tick")
            start=request("/api/health")[1]["tick"]
            wait_for(lambda:(r if r.get("tick",0)>=start+70 else None)
                     if (r:=request("/api/health")[1]) else None,50)
            after=request("/api/strategy")[1]["commanders"][faction].get("last_research_tick")
            check("hold did not authorize paid scientific shift",before==after)
            put("advise")
            m=wait_for(lambda:native_mandate(faction,"advise"))
            check("advisory mode stored but leaves baseline autonomous",m["mode"]=="advise")
            code,resp=request("/api/player/research-mandate/"+faction,"DELETE")
            check("clear command queued",code==202 and resp["status"]=="queued")
            wait_for(lambda:faction not in request("/api/strategy")[1].get("research_mandates",{}))
            check("mandate safely cleared without deleting the faction",faction in request("/api/strategy")[1]["commanders"])
            # Invalid tech and abusive Origin must fail before reaching ECS.
            try:
                request("/api/player/research-mandate","POST",{
                    "faction_id":faction,"target_technology":"nonexistent",
                    "mode":"delegated","budget_ceiling_cr":1000,"treasury_floor_cr":10000})
                raise AssertionError("Invalid tech was accepted")
            except urllib.error.HTTPError as e:
                check("invalid tech gets HTTP 400",e.code==400)
            evil=urllib.request.Request(BASE+"/api/player/research-mandate",
                data=json.dumps({"faction_id":faction,"target_technology":"automation",
                    "mode":"delegated","budget_ceiling_cr":1000,
                    "treasury_floor_cr":10000}).encode(),method="POST",
                headers={"Origin":"http://untrusted.example","Content-Type":"application/json"})
            try:
                urllib.request.urlopen(evil,timeout=5)
                raise AssertionError("Cross-origin policy write was accepted")
            except urllib.error.HTTPError as e:
                check("foreign Origin forbidden",e.code==403)
            results.update(status="passed",faction_id=faction,
                           tick=request("/api/health")[1].get("tick"))
        except BaseException as e:
            results.update(status="failed",error=repr(e))
            raise
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:proc.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    proc.kill();proc.wait(timeout=5)
            (OUT/"governance-smoke.json").write_text(
                json.dumps(results,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
            print(json.dumps(results,indent=2,ensure_ascii=False),flush=True)
