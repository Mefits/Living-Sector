#!/usr/bin/env python3
"""Galaxy 0.4.1 autonomous economic soak on a RELEASED Windows game ZIP.

No Cargo, user browser, previous save, or screenshots. The process uses
a fresh SQLite database, an actual Windows genesis_server.exe, official
/api/* snapshots, and real /ws events. Stages: 3k, 10k, 18k ticks.

Hard failures = server crash, hung ticks, inaccessible API or missing
checkpoint. Economic symptoms are warnings, NEVER mistaken for proof.
Artifacts contain equivalent Observer Diagnostics JSON, time series,
aggregated reports, and the original server log for reproducibility.
"""
from __future__ import annotations

import argparse
from collections import Counter, deque
import csv
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
import traceback
import urllib.error
import urllib.request

try:
    from websockets.sync.client import connect
except ImportError as exc:
    raise SystemExit("Install websockets==14.2 to capture native server /ws events") from exc

PORT = 18104
BASE = f"http://127.0.0.1:{PORT}"
FIELDS = (
    "tick", "elapsed_seconds", "world_seed", "ships", "stations",
    "colonies", "construction_sites", "ship_credits", "faction_treasuries",
    "facility_credits", "household_credits", "starving_colonies",
    "colonies_without_food_stock", "colonies_without_water_stock",
    "zero_credit_colonies", "paid_food_contracts", "paid_water_contracts",
    "paid_metals_contracts", "expired_contracts", "active_contracts",
    "stranded_refuel_ships", "fleet_levy_events", "rejected_ship_transactions",
)

def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")

def get(path: str, timeout: float = 12) -> dict:
    with urllib.request.urlopen(BASE + path, timeout=timeout) as res:
        if res.status != 200:
            raise RuntimeError(f"{path} returned HTTP {res.status}")
        payload = json.load(res)
        if not isinstance(payload, dict):
            raise RuntimeError(f"{path} did not return a JSON object")
        return payload

def v(source: dict, key: str, default=0):
    return source.get(key, default) if isinstance(source, dict) else default

def amount(values: list, key: str) -> int:
    return sum(int(v(obj, key)) for obj in values)

def status_counts(contracts: list, commodity: str | None = None) -> dict:
    counts = Counter(
        v(c, "status", "unknown") for c in contracts
        if commodity is None or v(c, "commodity") == commodity
    )
    return dict(sorted(counts.items()))

class EventCapture:
    """Native WebSocket events, not simulated transaction summaries."""
    def __init__(self, path: Path):
        self.path = path
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.count = 0
        self.event_types = Counter()
        self.reject_reasons = Counter()
        self.reject_by_ship = Counter()
        self.levies = Counter()
        self.last = deque(maxlen=1000)
        self.errors = []
        self.started = False
        self.thread = threading.Thread(target=self._run, name="galaxy-ws", daemon=True)

    def start(self):
        self.thread.start()

    def _run(self):
        with self.path.open("w", encoding="utf-8") as log:
            while not self.stop.is_set():
                try:
                    with connect(f"ws://127.0.0.1:{PORT}/ws",
                                 open_timeout=10, close_timeout=2,
                                 max_size=16*1024*1024) as ws:
                        self.started = True
                        while not self.stop.is_set():
                            try:
                                raw = ws.recv(timeout=1)
                            except TimeoutError:
                                continue
                            data = json.loads(raw)
                            if data.get("type") != "events":
                                continue
                            tick = data.get("tick")
                            for event in data.get("events", []):
                                if not isinstance(event, dict):
                                    continue
                                row = {"tick": tick, "event": event}
                                log.write(json.dumps(row, ensure_ascii=False,
                                                     separators=(",", ":")) + "\n")
                                kind = str(event.get("kind", "unknown"))
                                with self.lock:
                                    self.last.append(row)
                                    self.count += 1
                                    self.event_types[kind] += 1
                                    if kind == "ship_transaction_rejected":
                                        self.reject_reasons[str(event.get("reason"))] += 1
                                        self.reject_by_ship[str(event.get("ship_id"))] += 1
                                    elif kind == "ship_operating_levy":
                                        self.levies[str(event.get("faction_id"))] += int(event.get("amount", 0))
                            log.flush()
                except Exception as exc:
                    with self.lock:
                        if len(self.errors) < 30:
                            self.errors.append(f"{utc_now()}: {type(exc).__name__}: {exc}")
                    if not self.stop.wait(2):
                        continue

    def snapshot(self):
        with self.lock:
            return {
                "captured_events": self.count,
                "event_types": dict(self.event_types),
                "rejections_by_reason": dict(self.reject_reasons),
                "rejections_by_ship": dict(self.reject_by_ship.most_common(15)),
                "ship_operating_levies_cr": dict(self.levies),
                "recent_events_newest_first": list(reversed(self.last)),
                "websocket_errors": list(self.errors),
                "websocket_connected_at_least_once": self.started,
            }

    def close(self):
        self.stop.set()
        if self.thread.is_alive():
            self.thread.join(timeout=5)

def metrics(report: dict, contracts: list, events: dict, elapsed: float):
    ships = v(report, "ships", [])
    factions = v(report, "factions", [])
    facilities = v(report, "facilities", [])
    pops = v(report, "populations", [])
    markets = v(report, "markets", [])
    sites = v(report, "construction_sites", [])
    by_location = {m.get("facility_location"): m for m in markets}
    colonies = [p for p in pops
                if str(p.get("facility_location", "")).endswith("-colony")]
    market_stock = lambda p, item: float(
        v(v(by_location.get(p.get("facility_location")), "supply", {}), item, 0))
    return {
        "tick": int(v(report, "tick")),
        "elapsed_seconds": int(elapsed),
        "world_seed": v(report, "world_seed"),
        "ships": len(ships),
        "stations": sum(f.get("type") == "station" for f in facilities),
        "colonies": len(colonies),
        "construction_sites": len(sites),
        "ship_credits": amount(ships, "credits"),
        "faction_treasuries": amount(factions, "treasury"),
        "facility_credits": amount(facilities, "credits"),
        "household_credits": amount(pops, "total_wealth"),
        "starving_colonies": sum(float(v(p, "food_satisfaction", 100)) < 40 for p in colonies),
        "colonies_without_food_stock": sum(market_stock(p, "food") < 1 for p in colonies),
        "colonies_without_water_stock": sum(market_stock(p, "water") < 1 for p in colonies),
        "zero_credit_colonies": sum(int(v(p, "total_wealth")) <= 0 for p in colonies),
        "paid_food_contracts": sum(
            c.get("commodity") == "food" and c.get("status") == "paid"
            for c in contracts),
        "paid_water_contracts": sum(
            c.get("commodity") == "water" and c.get("status") == "paid"
            for c in contracts),
        "paid_metals_contracts": sum(
            c.get("commodity") == "metals" and c.get("status") == "paid"
            for c in contracts),
        "expired_contracts": sum(c.get("status") == "expired" for c in contracts),
        "active_contracts": sum(c.get("status") in ("posted", "accepted", "picked_up", "delivered")
                                for c in contracts),
        "stranded_refuel_ships": sum(s.get("current_goal") == "refuel" and
                                    float(v(s, "fuel")) < 0.01 for s in ships),
        "fleet_levy_events": events.get("event_types", {}).get("ship_operating_levy", 0),
        "rejected_ship_transactions": events.get("event_types", {}).get(
            "ship_transaction_rejected", 0),
    }

def detail(report, contracts, strategy):
    sites = v(report, "construction_sites", [])
    facilities = v(report, "facilities", [])
    markets = {m.get("facility_location"):m for m in v(report, "markets", [])}
    pops = v(report, "populations", [])
    stations = [x for x in facilities if x.get("type") == "station"]
    station_buildings = []
    for station in stations:
        owned = lambda row: (row.get("location") == station.get("location")
                              and row.get("faction_id") == station.get("faction_id"))
        built = [f for f in facilities if owned(f) and f.get("type") != "station"]
        in_progress = [s for s in sites if owned(s)]
        station_buildings.append({
            "location": station.get("location"),
            "faction_id": station.get("faction_id"),
            "built_count": len(built),
            "built_types": [f.get("type") for f in built],
            "construction_count": len(in_progress),
            "projects": [s.get("facility_type") for s in in_progress],
            "visual_t1_occupancy": len(built) + len(in_progress),
        })
    colonies = []
    for p in pops:
        loc = p.get("facility_location")
        if not str(loc).endswith("-colony"):
            continue
        m = markets.get(loc)
        stock = v(m, "supply", {})
        colonies.append({
            "location":loc,
            "population":p.get("population_count"),
            "food_satisfaction":p.get("food_satisfaction"),
            "household_credits":p.get("total_wealth"),
            "food_stock":stock.get("food") if m else None,
            "water_stock":stock.get("water") if m else None,
            "fuel_stock":stock.get("fuel") if m else None,
            "market_present":m is not None,
        })
    return {
        "colonies":colonies,
        "station_buildings":station_buildings,
        "construction_sites":[{
            "id":s.get("id"),
            "location":s.get("location"),
            "faction_id":s.get("faction_id"),
            "facility_type":s.get("facility_type"),
            "delivered":s.get("progress_delivered"),
            "required":s.get("progress_required"),
            "labor_completed":v(s.get("labor"), "completed"),
            "labor_required":v(s.get("labor"), "required"),
            "reason":v(s.get("labor"), "blocked_reason", None),
        } for s in sites],
        "contracts_by_status":status_counts(contracts),
        "food_contracts_by_status":status_counts(contracts, "food"),
        "water_contracts_by_status":status_counts(contracts, "water"),
        "fuel_contracts_by_status":status_counts(contracts, "fuel"),
        "station_orders_by_state":dict(Counter(
            v(o, "state", "unknown") for o in v(strategy, "orders", []))),
        "station_order_blocks":dict(Counter(
            v(o, "blocked_reason") for o in v(strategy, "orders", [])
            if v(o, "blocked_reason", None))),
        "colony_goals":[{
            "faction_id":c.get("faction_id"), "location":c.get("location"),
            "phase":c.get("phase"), "reason":c.get("reason"),
            "next_commodity":c.get("next_commodity"),
        } for c in v(strategy, "colonies", [])],
    }

def economic_warnings(checkpoints: list):
    warnings=[]
    if not checkpoints:
        return ["No checkpoints were recorded"]
    last = checkpoints[-1]
    met=last["metrics"]
    det=last["detail"]
    if met["starving_colonies"]:
        warnings.append(f"{met['starving_colonies']} populated colonies have food satisfaction below 40")
    if met["colonies_without_food_stock"]:
        warnings.append(f"{met['colonies_without_food_stock']} colonies have less than 1 unit of food")
    if met["zero_credit_colonies"]:
        warnings.append(f"{met['zero_credit_colonies']} colonies have no household credits")
    if met["ship_credits"] > 10 * max(1, met["facility_credits"] + met["faction_treasuries"]):
        warnings.append("Ships hold >10x the combined facility/faction cash (liquidity trap)")
    for site in det["construction_sites"]:
        older=checkpoints[0]["detail"]["construction_sites"]
        previous=next((s for s in older if s["id"]==site["id"]),None)
        if previous and previous.get("delivered")==site.get("delivered") and (
            site.get("reason") or previous.get("reason")
        ):
            warnings.append(f"Construction {site['id']} has no material progress across checkpoints")
    rejected=last["events"]["rejections_by_reason"]
    for reason, count in sorted(rejected.items()):
        if count >= 20:
            warnings.append(f"Repeated transaction rejection {reason}: {count}")
    if not last["events"]["websocket_connected_at_least_once"]:
        warnings.append("WebSocket event monitoring never connected; error counts unavailable")
    if len(checkpoints)>1:
        first,latest=checkpoints[0]["metrics"],last["metrics"]
        if latest["paid_food_contracts"]<=first["paid_food_contracts"] and latest["colonies"]>0:
            warnings.append("No additional paid food contracts between first and final checkpoints")
    return warnings

def emit_markdown(summary: dict, output: Path):
    checks=summary.get("checkpoints",[])
    lines=[
        "# Galaxy 0.4.1 — автономное испытание экономики",
        "",
        f"**Результат:** {summary.get('status')}  ·  **Сборка:** {summary.get('build_sha','unknown')}",
        f"**Начало:** {summary.get('started_utc')}  ·  **Конец:** {summary.get('finished_utc','—')}",
        "",
        "| Тик | Колонии | Голод | Еды нет | CR кораблей | CR предприятий | CR казн | Оплачено доставок еды |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for cp in checks:
        m=cp["metrics"]
        lines.append("| "+ " | ".join(str(m[k]) for k in (
            "tick","colonies","starving_colonies","colonies_without_food_stock",
            "ship_credits","facility_credits","faction_treasuries","paid_food_contracts"))+" |")
    lines+=["", "### Диагностические предупреждения"]
    lines+=["- "+w for w in summary.get("warnings",[])] or ["- Критичных симптомов по текущим правилам не обнаружено"]
    lines+=["","### Что доказано этим прогоном",
        "- Сервер реально работал до указанного тика, API был доступен, SQLite создавалась на чистом мире.",
        "- Денежные остатки взяты из реального API. Это НЕ доказательство глобального сохранения денежной массы.",
        "- События WebSocket захватывались во время работы, а не восстановлены из неполной истории.",
        "- Экономические предупреждения — диагностические сигналы. Важна динамика и реальные контракты.",
        "- Результат НЕ заменяет ручную игровую оценку интерфейса.",
        "",
        "### Архивные данные",
        "- checkpoints/*-diagnostics.json: API-снимок в формате Observer, включая последние 1000 WS событий.",
        "- checkpoints/*-analysis.json: расчёт и список проблемных строек/колоний.",
        "- events.jsonl: реальные события WebSocket, если подключение было доступно.",
        "- telemetry.csv: динамика показателей, снимки каждые 600 тиков.",
        "- genesis_server.log: серверный журнал с ошибками и предупреждениями.",
    ]
    output.write_text("\n".join(lines)+"\n",encoding="utf-8")
    github=os.environ.get("GITHUB_STEP_SUMMARY")
    if github:
        with open(github,"a",encoding="utf-8") as f:
            f.write("\n".join(lines)+"\n")

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--game-dir",type=Path,required=True)
    parser.add_argument("--output",type=Path,default=Path("autonomous-bench-results"))
    parser.add_argument("--targets",default="3000,10000,18000")
    parser.add_argument("--sample-every",type=int,default=600)
    parser.add_argument("--timeout-seconds",type=int,default=2700)
    args=parser.parse_args()
    targets=sorted({int(n.strip()) for n in args.targets.split(",")})
    if len(targets)!=3 or targets[0]<=0 or args.sample_every<100:
        raise ValueError("Expected 3 positive checkpoints and sample-every>=100")
    project=args.game_dir.resolve()
    exe=project/"Genesis-Server.exe"
    data=project/"priv/galaxy/data"
    observer=project/"observer"
    if not (exe.is_file() and data.is_dir() and observer.is_dir()):
        raise FileNotFoundError(f"Not a complete portable game: {project}")
    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=True)
    (out/"checkpoints").mkdir(exist_ok=True)
    import tempfile
    import shutil
    scratch=Path(tempfile.mkdtemp(prefix="galaxy041-bench-"))
    start=time.monotonic()
    summary={
        "format":"living-sector-autonomous-bench-v1",
        "status":"running","build_sha":os.environ.get("GITHUB_SHA"),
        "started_utc":utc_now(),"targets":targets,
        "checkpoints":[],"warnings":[],
        "data_note":"Every checkpoint is a real server state. Events reflect this harness's WebSocket connection, not the user's old session.",
    }
    tap=EventCapture(out/"events.jsonl")
    process=None
    try:
        with (out/"genesis_server.log").open("wb") as log:
            env=os.environ.copy()
            env.update({
                "DATA_DIR":str(data),
                "DATABASE_PATH":str(scratch/"bench041.db"),
                "LIVING_SECTOR_UI_DIR":str(observer),
                "LIVING_SECTOR_GALAXY":"1",
                "LIVING_SECTOR_STRATEGY_MODE":"execute",
                "LIVING_SECTOR_PLANNER":"hybrid",
                "LIVING_SECTOR_PLANNER_SHADOW":"0",
                "LIVING_SECTOR_PLANNER_COMPARE":"0",
                "BIND_ADDR":f"127.0.0.1:{PORT}",
                "WORLD_SPEED":"16",
                "RUST_LOG":"sim_core=warn,sim_db=info,sim_server=info",
            })
            process=subprocess.Popen([str(exe)], cwd=project, env=env,
                                     stdout=log, stderr=subprocess.STDOUT)
            last_error=""
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError(f"server exited during startup: {process.returncode}")
                try:
                    health=get("/api/health")
                    if health.get("running") and health.get("status")=="ok":
                        break
                except Exception as error:
                    last_error=str(error)
                time.sleep(1)
            else:
                raise RuntimeError("server startup timeout: "+last_error)
            tap.start()
            last_tick=int(health.get("tick",0))
            last_progress=time.monotonic()
            next_sample=args.sample_every
            checkpoints=targets.copy()
            csv_path=out/"telemetry.csv"
            with csv_path.open("w",encoding="utf-8",newline="") as csv_file:
                writer=csv.DictWriter(csv_file,fieldnames=FIELDS)
                writer.writeheader()
                while checkpoints:
                    if process.poll() is not None:
                        raise RuntimeError(f"server exited at tick {last_tick} with {process.returncode}")
                    if time.monotonic()-start>args.timeout_seconds:
                        raise TimeoutError(f"bench global timeout at tick {last_tick}")
                    try:
                        health=get("/api/health",timeout=8)
                    except Exception as ex:
                        if time.monotonic()-last_progress>120:
                            raise RuntimeError(f"health API unavailable: {ex}") from ex
                        time.sleep(2)
                        continue
                    tick=int(health.get("tick",0))
                    if tick>last_tick:
                        last_tick=tick
                        last_progress=time.monotonic()
                    if time.monotonic()-last_progress>150:
                        raise RuntimeError(f"simulation stalled at tick {tick} for 150 seconds")
                    if len(checkpoints)==len(targets) and tick<100:
                        time.sleep(1.2)
                        continue
                    if tick>=next_sample or tick>=checkpoints[0]:
                        report=get("/api/report",timeout=35)
                        contracts_response=get("/api/contracts",timeout=15)
                        contracts=contracts_response.get("data",[])
                        events=tap.snapshot()
                        row=metrics(report,contracts,events,time.monotonic()-start)
                        writer.writerow({field:row.get(field) for field in FIELDS})
                        csv_file.flush()
                        next_sample=max(next_sample+args.sample_every,
                                        tick+args.sample_every)
                        if tick>=checkpoints[0]:
                            checkpoint=checkpoints.pop(0)
                            strategy=get("/api/strategy",timeout=35)
                            snapshot_tick=int(report.get("tick",tick))
                            stamp=f"t{checkpoint:05d}"
                            diagnostics={
                                "format":"living-sector-observer-diagnostics-v1",
                                "captured_at":utc_now(),
                                "source":"automated GitHub Actions Windows runner",
                                "note":"Real HTTP snapshots and live WebSocket events from this single session.",
                                "snapshot_tick_at_export":snapshot_tick,
                                "browser_events_newest_first":events["recent_events_newest_first"],
                                "browser_event_count":len(events["recent_events_newest_first"]),
                                "browser_event_capacity":1000,
                                "endpoints":{
                                    key:{"ok":True,"value":value} for key,value in {
                                        "health":health,
                                        "report":report,
                                        "strategy":strategy,
                                        "contracts":contracts_response,
                                    }.items()
                                }
                            }
                            path=out/"checkpoints"/f"{stamp}-diagnostics.json"
                            path.write_text(json.dumps(diagnostics,ensure_ascii=False,
                                separators=(",",":")),encoding="utf-8")
                            cp={
                                "requested_tick":checkpoint,"actual_tick":snapshot_tick,
                                "metrics":row,"detail":detail(report,contracts,strategy),
                                "events":{k:v for k,v in events.items()
                                          if k!="recent_events_newest_first"},
                                "diagnostics_file":path.name
                            }
                            (out/"checkpoints"/f"{stamp}-analysis.json").write_text(
                                json.dumps(cp,ensure_ascii=False,indent=2),encoding="utf-8")
                            summary["checkpoints"].append(cp)
                            summary["last_tick"]=snapshot_tick
                            summary["world_seed"]=report.get("world_seed")
                            (out/"summary.json").write_text(json.dumps(summary,
                                ensure_ascii=False,indent=2),encoding="utf-8")
                            print(f"CHECKPOINT {checkpoint}: actual={snapshot_tick}, "
                                  f"colonies={row['colonies']}, starving={row['starving_colonies']}, "
                                  f"ship_CR={row['ship_credits']}, facility_CR={row['facility_credits']}",
                                  flush=True)
                    time.sleep(1.3)
            if len(summary["checkpoints"])!=3:
                raise RuntimeError("Did not record all three mandatory checkpoints")
            if len(v(report, "systems", []))!=8 or len(v(report, "factions", []))!=3:
                raise RuntimeError("A required star system or faction disappeared")
            if len(v(report, "system_links", []))!=8:
                raise RuntimeError("Runtime navigation no longer has eight real corridors")
            summary["status"]="passed_runtime"
            summary["warnings"]=economic_warnings(summary["checkpoints"])
    except BaseException as ex:
        summary["status"]="failed_runtime"
        summary["error"]=f"{type(ex).__name__}: {ex}"
        summary["traceback"]=traceback.format_exc()
        print(summary["error"],file=sys.stderr,flush=True)
        raise
    finally:
        tap.close()
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=12)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=6)
        # The Windows server must terminate before SQLite's WAL/file handles
        # can be removed. Never let temporary-file cleanup reclassify a
        # completed 18k-tick game run as a failed runtime.
        try:
            shutil.rmtree(scratch)
        except (OSError, PermissionError) as cleanup_error:
            print(f"Deferred Windows scratch cleanup: {cleanup_error}",flush=True)
        summary["finished_utc"]=utc_now()
        summary["elapsed_seconds"]=int(time.monotonic()-start)
        (out/"summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),
                                        encoding="utf-8")
        emit_markdown(summary,out/"REPORT-RU.md")
        # Descriptive old-vs-new snapshots: a different world seed means
        # this cannot, by itself, prove causal improvement.
        try:
            from compare_baseline import make_comparison, render_markdown
            old=json.loads((Path(__file__).parent/"legacy_baseline.json")
                           .read_text(encoding="utf8"))
            comparison=make_comparison(old,summary)
            (out/"baseline_comparison.json").write_text(
                json.dumps(comparison,ensure_ascii=False,indent=2)+"\n",
                encoding="utf8")
            (out/"BASELINE-COMPARISON-RU.md").write_text(
                render_markdown(comparison),encoding="utf8")
        except Exception as exception:
            print(f"Baseline report failed: {type(exception).__name__}: {exception}",
                  file=sys.stderr,flush=True)
        print(f"BENCH RESULT: {summary['status']}, "
              f"checkpoints={len(summary['checkpoints'])}, "
              f"warnings={len(summary['warnings'])}",flush=True)

if __name__=="__main__":
    main()
