#!/usr/bin/env python3
"""Short REAL Windows x16 Sol S0 telemetry capture from a known successful ZIP.

No player commands; fresh SQLite; native HTTP + WS evidence only.
Never labels this run successful economic relief. Analyzer must do that
separately when a strict native cargo receipt and background exist.
"""
from __future__ import annotations
import argparse,hashlib,json,os,subprocess,sys,tempfile,threading,time
from datetime import datetime,timezone
from pathlib import Path
from urllib.request import urlopen
from collections import Counter
from analyze import read_jsonl,write_result

try:
    from websockets.sync.client import connect
except ImportError:
    raise SystemExit("pip install websockets==14.2 before S0 capture")

HOST="http://127.0.0.1:18114"
WS="ws://127.0.0.1:18114/ws"
def get(path,timeout=20):
    with urlopen(HOST+path,timeout=timeout) as r:
        if r.status!=200:raise RuntimeError(f"{path}: HTTP {r.status}")
        j=json.load(r)
        if not isinstance(j,dict):raise RuntimeError(f"{path} is not an object")
        return j

class Tap:
    def __init__(self,path:Path):
        self.path=path;self.stop=threading.Event()
        self.kinds=Counter();self.errors=[]
        self.connected=False;self.count=0
        self.thread=threading.Thread(target=self.run,daemon=True)
    def run(self):
        with self.path.open("w",encoding="utf8") as log:
            while not self.stop.is_set():
                try:
                    with connect(WS,open_timeout=8,close_timeout=2,
                                 max_size=12*1024*1024) as ws:
                        self.connected=True
                        while not self.stop.is_set():
                            try:msg=ws.recv(timeout=1.0)
                            except TimeoutError:continue
                            data=json.loads(msg)
                            if data.get("type")!="events":continue
                            for e in data.get("events",[]):
                                if not isinstance(e,dict):continue
                                log.write(json.dumps({"tick":data.get("tick"),"event":e},
                                    ensure_ascii=False)+"\n")
                                self.count+=1
                                self.kinds[str(e.get("kind","unknown"))]+=1
                            log.flush()
                except Exception as exc:
                    if len(self.errors)<15:self.errors.append(repr(exc))
                    self.stop.wait(2)
    def start(self):self.thread.start()
    def close(self):
        self.stop.set()
        if self.thread.is_alive():self.thread.join(timeout=5)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--game-dir",type=Path,required=True)
    p.add_argument("--out",type=Path,default=Path("sol-s0-results"))
    p.add_argument("--ticks",type=int,default=1800)
    p.add_argument("--sample-every",type=int,default=120)
    p.add_argument("--max-seconds",type=int,default=620)
    p.add_argument("--source-run",type=str,default="42990801593")
    args=p.parse_args()
    if args.ticks<300 or args.sample_every<20:
        raise ValueError("S0 must collect a meaningful sampled run")
    game=args.game_dir.resolve()
    exe=game/"Genesis-Server.exe"
    if not (exe.is_file() and (game/"priv/galaxy/data").is_dir()):
        raise FileNotFoundError(f"Not a standalone Genesis ZIP: {game}")
    binary_hash=hashlib.sha256(exe.read_bytes()).hexdigest()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    manifest={"format":"sol-s0-capture-v1","source_workflow_run":args.source_run,
              "game_exe_sha256":binary_hash,
              "build_source_sha":"4ffd80002ec74b4af3eccb0db5279578c1148e0a",
              "started_utc":datetime.now(timezone.utc).isoformat(),
              "fresh_sqlite":True,"strategy_mode":"execute","planner":"hybrid",
              "world_speed":16,"target_ticks":args.ticks,
              "sample_every":args.sample_every,"status":"running"}
    def flush():
        (out/"manifest.json").write_text(
            json.dumps(manifest,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
    flush()
    with tempfile.TemporaryDirectory(prefix="sol-s0-clean-") as d:
        env=os.environ.copy()
        env.update({"BIND_ADDR":"127.0.0.1:18114",
           "DATABASE_PATH":str(Path(d)/"clean-sol-s0.db"),
           "DATA_DIR":str(game/"priv/galaxy/data"),
           "LIVING_SECTOR_UI_DIR":str(game/"observer"),
           "LIVING_SECTOR_GALAXY":"1",
           "LIVING_SECTOR_STRATEGY_MODE":"execute",
           "LIVING_SECTOR_PLANNER":"hybrid",
           "LIVING_SECTOR_PLANNER_SHADOW":"0",
           "LIVING_SECTOR_PLANNER_COMPARE":"0",
           "WORLD_SPEED":"16",
           "RUST_LOG":"sim_server=info,sim_core=warn"})
        start=time.monotonic();last_progress=start;last_tick=-1
        samples_path=out/"samples.jsonl"
        events_path=out/"events.jsonl"
        tap=Tap(events_path);process=None
        try:
            with (out/"genesis-server.log").open("wb") as log:
                process=subprocess.Popen([str(exe)],cwd=game,env=env,
                    stdout=log,stderr=subprocess.STDOUT)
                for _ in range(90):
                    if process.poll() is not None:raise RuntimeError(
                        f"Genesis quit during startup code {process.returncode}")
                    try:
                        h=get("/api/health",5)
                        if h.get("status")=="ok" and h.get("running"):break
                    except Exception:pass
                    time.sleep(1)
                else:raise TimeoutError("Genesis S0 startup not healthy")
                tap.start()
                next_sample=0;counts=0
                with samples_path.open("w",encoding="utf8") as f:
                    while True:
                        if process.poll() is not None:raise RuntimeError(
                            f"Genesis exited at tick {last_tick}")
                        elapsed=time.monotonic()-start
                        if elapsed>args.max_seconds:raise TimeoutError(
                            f"S0 timed out at tick {last_tick}")
                        try:health=get("/api/health",12)
                        except Exception:
                            time.sleep(1.5);continue
                        tick=int(health.get("tick",0))
                        if tick>last_tick:
                            last_tick=tick;last_progress=time.monotonic()
                        elif time.monotonic()-last_progress>110:
                            raise TimeoutError(f"Genesis stalled at tick {tick}")
                        if tick>=next_sample or (tick>=args.ticks and counts):
                            report=get("/api/report",35)
                            strategy=get("/api/strategy",35)
                            contracts=get("/api/contracts",20)
                            sample={"health":health,"report":report,
                                    "strategy":strategy,
                                    "contracts":contracts.get("data",[])}
                            f.write(json.dumps(sample,ensure_ascii=False)+"\n")
                            f.flush()
                            counts+=1
                            next_sample=tick+args.sample_every
                            print(f"Real S0 sample #{counts}: tick {tick}, "
                                  f"contracts {len(sample['contracts'])}",flush=True)
                        if tick>=args.ticks and counts>=2:break
                        time.sleep(1.4)
                if not (Path(d)/"clean-sol-s0.db").is_file():
                    raise RuntimeError("Fresh SQLite never created")
                manifest.update(status="captured",tick=last_tick,samples=counts,
                    observed_ws_events=tap.count,websocket_connected=tap.connected,
                    ws_kinds=dict(tap.kinds),ws_errors=tap.errors)
        except BaseException as exc:
            manifest.update(status="failed",error=repr(exc),tick=last_tick)
            raise
        finally:
            tap.close()
            if process is not None and process.poll() is None:
                process.terminate()
                try:process.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    process.kill();process.wait(timeout=6)
            flush()
    if not samples_path.exists():raise RuntimeError("Missing S0 snapshots")
    result=write_result(read_jsonl(samples_path),read_jsonl(events_path),
        out,manifest["build_source_sha"])
    manifest.update(analyzer_conclusion=result["conclusion"])
    flush()
    print((out/"REPORT-RU.md").read_text(encoding="utf8"),flush=True)

if __name__=="__main__":main()
