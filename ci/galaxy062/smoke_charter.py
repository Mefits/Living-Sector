#!/usr/bin/env python3
"""One short Windows smoke of the actual native charter control queue.

No manual ship control; no fictitious completion assertions. Separate
fresh SQLite database, never touches installed stable game saves.
"""
from __future__ import annotations
import json,os,subprocess,tempfile,time,urllib.request,urllib.error
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/"work/source/Living-Sector-Galaxy-0.2"
EXE=SOURCE/"target/release/genesis_server.exe"
OUT=ROOT/"charter-smoke-results"
OUT.mkdir(exist_ok=True)
BASE="http://127.0.0.1:18108"
evidence={"status":"not_run","checks":[]}

def api(path,method="GET",body=None,headers=None):
    h=dict(headers or {})
    data=None if body is None else json.dumps(body).encode("utf8")
    if data is not None:h["Content-Type"]="application/json"
    req=urllib.request.Request(BASE+path,method=method,data=data,headers=h)
    with urllib.request.urlopen(req,timeout=12) as res:
        return res.status,json.load(res)

def expect(label,assertion):
    if not assertion:raise AssertionError(label)
    evidence["checks"].append(label)

def await_state(predicate,limit=70):
    until=time.monotonic()+limit
    while time.monotonic()<until:
        if process.poll() is not None:raise RuntimeError(f"server exited {process.returncode}")
        try:
            got=predicate()
            if got is not None and got is not False:return got
        except (urllib.error.URLError,TimeoutError,ValueError):
            pass
        time.sleep(.6)
    raise TimeoutError("native charter state did not appear on the running server")

with tempfile.TemporaryDirectory(prefix="galaxy062-smoke-") as folder:
    env=os.environ.copy()
    env.update({
        "BIND_ADDR":"127.0.0.1:18108",
        "DATABASE_PATH":str(Path(folder)/"charter-world.db"),
        "DATA_DIR":str(SOURCE/"priv/galaxy/data"),
        "LIVING_SECTOR_UI_DIR":str(SOURCE/"observer"),
        "LIVING_SECTOR_GALAXY":"1",
        "LIVING_SECTOR_STRATEGY_MODE":"execute",
        "LIVING_SECTOR_PLANNER":"hybrid",
        "LIVING_SECTOR_PLANNER_SHADOW":"0",
        "LIVING_SECTOR_PLANNER_COMPARE":"0",
        "WORLD_SPEED":"16",
        "RUST_LOG":"sim_server=info,sim_core=warn"
    })
    with (OUT/"native-server.log").open("wb") as log:
        process=subprocess.Popen([str(EXE)],cwd=SOURCE,
            env=env,stdout=log,stderr=subprocess.STDOUT)
        try:
            strategy=await_state(lambda:(d if d.get("commanders") else None)
                if (d:=api("/api/strategy")[1]) else None,90)
            expect("native Genesis commanders initialized",
                len(strategy["commanders"])==3)
            expect("old save defaults to no faction charter",
                not strategy.get("faction_charters"))
            faction=sorted(strategy["commanders"])[0]
            page=urllib.request.urlopen(BASE+"/observer/governance-charter.html",
                timeout=8).read()
            expect("real charter console HTML served",
                b"/api/player/faction-charter" in page)
            body={
                "faction_id":faction,
                "research_authority":"delegated",
                "economy_authority":"review",
                "research_priority":70,
                "economy_priority":35,
                "shared_ceiling_cr":30000,
                "protected_treasury_cr":10000,
                "approved_research_cr":0,
                "approved_economy_cr":0,
            }
            code,reply=api("/api/player/faction-charter","POST",body)
            expect("HTTP 202 means queued, not success",code==202
                and reply.get("status")=="queued")
            def read_charter():
                c=api("/api/strategy")[1].get("faction_charters",{}).get(faction)
                return c if c and c.get("research_priority")==70 else None
            c=await_state(read_charter)
            expect("actual ECS faction charter applied on engine tick",
                c["economy_authority"]=="review"
                and c["shared_ceiling_cr"]==30000)
            expect("unspent first mandate cannot mint credits",
                c["spent_cr"]==0 and c["spent_economy_cr"]==0)
            expect("only selected faction received charter",
                set(api("/api/strategy")[1].get("faction_charters",{}))=={faction})
            body.update(economy_authority="delegated",research_priority=45,
                economy_priority=80,approved_economy_cr=2000)
            code,_=api("/api/player/faction-charter","POST",body)
            expect("updating charter only queues another native command",code==202)
            c=await_state(lambda:(x if x and x.get("economy_priority")==80 else None)
                if (x:=api("/api/strategy")[1].get("faction_charters",{}).get(faction)) else None)
            expect("priority/review approval applied without ledger erasure",
                c["approved_economy_cr"]==2000
                and c["spent_cr"]==0
                and c["research_priority"]==45)
            invalid=dict(body,shared_ceiling_cr=1)
            try:
                api("/api/player/faction-charter","POST",invalid)
                raise AssertionError("invalid ceiling was accepted")
            except urllib.error.HTTPError as exc:
                expect("invalid mandate shared ceiling rejected at HTTP",exc.code==400)
            try:
                api("/api/player/faction-charter","POST",body,
                    headers={"Origin":"http://malicious.example"})
                raise AssertionError("foreign Origin was accepted")
            except urllib.error.HTTPError as exc:
                expect("cross-origin policy mutation blocked",exc.code==403)
            try:
                api("/api/player/faction-charter","POST",dict(body,
                    faction_id="invented-unknown-faction"))
                raise AssertionError("invented faction accepted")
            except urllib.error.HTTPError as exc:
                expect("unknown faction rejected by real snapshot",exc.code==404)
            expect("after rejected commands saved actual charter unchanged",
                api("/api/strategy")[1]["faction_charters"][faction]
                    ["economy_priority"]==80)
            evidence.update(status="passed",faction=faction,
                note="Engine confirmed configuration. This test does not claim long-run contract delivery or full save/restart roundtrip.")
        except BaseException as exc:
            evidence.update(status="failed",error=repr(exc))
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    process.kill();process.wait(timeout=5)
            (OUT/"charter-smoke.json").write_text(
                json.dumps(evidence,indent=2,ensure_ascii=False)+"\n",
                encoding="utf8")
            print(json.dumps(evidence,indent=2,ensure_ascii=False),flush=True)
