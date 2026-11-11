#!/usr/bin/env python3
"""Galaxy 0.6.3 short Windows live smoke.

Always tests real server control, origin and stale/replayed proposal
protection. A fully executable quote depends on actual markets/routes;
the separate native ECS fixture proves quote -> payment -> receipt.
"""
from __future__ import annotations
import json,os,subprocess,tempfile,time,urllib.request,urllib.error
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/"work/source/Living-Sector-Galaxy-0.2"
EXE=SRC/"target/release/genesis_server.exe"
OUT=ROOT/"specific-approval-smoke-results"
OUT.mkdir(exist_ok=True)
BASE="http://127.0.0.1:18109"
evidence={"status":"not_run","checks":[]}

def call(path,method="GET",body=None,headers=None):
    data=json.dumps(body).encode("utf8") if body is not None else None
    h=dict(headers or {})
    if data is not None:h["Content-Type"]="application/json"
    q=urllib.request.Request(BASE+path,method=method,data=data,headers=h)
    with urllib.request.urlopen(q,timeout=12) as r:return r.status,json.load(r)

def check(name,condition):
    if not condition:raise AssertionError(name)
    evidence["checks"].append(name)

def until(fn,seconds=70):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        if process.poll() is not None:raise RuntimeError(f"server exit {process.returncode}")
        try:
            value=fn()
            if value:return value
        except (urllib.error.URLError,TimeoutError,ValueError):
            pass
        time.sleep(.65)
    raise TimeoutError("real game did not expose state")

with tempfile.TemporaryDirectory(prefix="galaxy063-live-") as folder:
    env=os.environ.copy()
    env.update({
        "BIND_ADDR":"127.0.0.1:18109",
        "DATABASE_PATH":str(Path(folder)/"world.db"),
        "DATA_DIR":str(SRC/"priv/galaxy/data"),
        "LIVING_SECTOR_UI_DIR":str(SRC/"observer"),
        "LIVING_SECTOR_GALAXY":"1",
        "LIVING_SECTOR_STRATEGY_MODE":"execute",
        "LIVING_SECTOR_PLANNER":"hybrid",
        "LIVING_SECTOR_PLANNER_SHADOW":"0",
        "LIVING_SECTOR_PLANNER_COMPARE":"0",
        "WORLD_SPEED":"16",
        "RUST_LOG":"sim_server=info,sim_core=warn",
    })
    with (OUT/"native-server.log").open("wb") as log:
        process=subprocess.Popen([str(EXE)],cwd=SRC,env=env,
            stdout=log,stderr=subprocess.STDOUT)
        try:
            initial=until(lambda:(s if s.get("commanders") else None)
                if (s:=call("/api/strategy")[1]) else None,90)
            check("original Genesis real directors",len(initial["commanders"])==3)
            check("fresh world has no action proposals",not initial.get("economic_proposals"))
            page=urllib.request.urlopen(BASE+"/observer/governance-approvals.html",
                timeout=8).read()
            check("actual review console served",b"/api/player/economic-proposal/decision" in page)
            report=call("/api/report")[1]
            owned=[f for f in report.get("facilities",[])
                if f.get("type")=="station" and f.get("faction_id") in initial["commanders"]]
            check("actual owned station exists",bool(owned))
            station=sorted(owned,key=lambda f:(f.get("faction_id",""),f.get("location","")))[0]
            faction=station["faction_id"];location=station["location"]
            charter={
                "faction_id":faction,
                "research_authority":"delegated","economy_authority":"review",
                "research_priority":45,"economy_priority":75,
                "shared_ceiling_cr":50000,"protected_treasury_cr":10000,
                "approved_research_cr":0,"approved_economy_cr":0,
            }
            code,result=call("/api/player/faction-charter","POST",charter)
            check("specific review charter command queued",code==202 and result["status"]=="queued")
            until(lambda:(c if c and c.get("economy_authority")=="review" else None)
                if (c:=call("/api/strategy")[1].get("faction_charters",{}).get(faction))
                else None)
            code,result=call("/api/player/economic-mandate","POST",{
                "faction_id":faction,"location":location,"commodity":"water",
                "kind":"supply","min_stock":5000,"mode":"delegated",
                "budget_ceiling_cr":40000,"treasury_floor_cr":10000
            })
            check("native economic mandate queued",code==202 and result["status"]=="queued")
            until(lambda:(m if m and m.get("mode")=="delegated" else None)
                if (m:=call("/api/strategy")[1].get("economic_mandates",{}).get(faction))
                else None)
            bad={"faction_id":faction,"proposal_id":"forged-economic-123","approve":True}
            code,reply=call("/api/player/economic-proposal/decision","POST",bad)
            check("forged proposal request only queued",code==202 and reply["status"]=="queued")
            # Do NOT turn an invalid HTTP queue receipt into a permission.
            time.sleep(1.4)
            state=call("/api/strategy")[1]
            prop=state.get("economic_proposals",{}).get(faction)
            check("fake proposal cannot become approved",
                not prop or prop.get("status")!="approved")
            try:
                call("/api/player/economic-proposal/decision","POST",bad,
                    headers={"Origin":"http://attacker.invalid"})
                raise AssertionError("foreign origin wrongly accepted")
            except urllib.error.HTTPError as exc:
                check("cross-origin approvals forbidden",exc.code==403)
            try:
                call("/api/player/economic-proposal/decision","POST",
                    {**bad,"proposal_id":""})
                raise AssertionError("empty proposal id accepted")
            except urllib.error.HTTPError as exc:
                check("empty proposal id rejected",exc.code==400)
            try:
                call("/api/player/economic-proposal/decision","POST",
                    {**bad,"faction_id":"invented-faction"})
                raise AssertionError("unknown faction accepted")
            except urllib.error.HTTPError as exc:
                check("unknown faction rejected",exc.code==404)
            if prop and prop.get("status")=="pending":
                proposal_id=prop["proposal_id"]
                code,reply=call("/api/player/economic-proposal/decision","POST",{
                    "faction_id":faction,"proposal_id":proposal_id,"approve":False})
                check("decline a real native quote queued",code==202)
                try:
                    until(lambda:(p if p and p.get("status")=="rejected" else None)
                        if (p:=call("/api/strategy")[1].get("economic_proposals",{}).get(faction))
                        and p.get("proposal_id")==proposal_id else None,20)
                    check("decline confirmed in real engine",True)
                except TimeoutError:
                    evidence["note"]="Native quote rotated before decline confirmation, no fake success asserted."
            else:
                evidence["note"]="No native ready water quote in this short live run; native paid fixture covers approval-to-payment."
            evidence.update(status="passed",faction=faction,location=location)
        except BaseException as exc:
            evidence.update(status="failed",error=repr(exc))
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    process.kill();process.wait(timeout=4)
            (OUT/"specific-approval-smoke.json").write_text(
                json.dumps(evidence,indent=2,ensure_ascii=False)+"\n",
                encoding="utf8")
            print(json.dumps(evidence,indent=2,ensure_ascii=False),flush=True)
