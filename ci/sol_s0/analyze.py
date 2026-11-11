#!/usr/bin/env python3
"""Sol S0 inventory and conservative golden assessment. No invented relief.

Consumes REAL Genesis report/strategy/contracts snapshots and WebSocket events.
Never marks relief verified from only a paid contract or stock change.
"""
from __future__ import annotations
import argparse,json
from collections import Counter
from pathlib import Path

COMMODITIES=("food","water","fuel","gas")
STATION="earth-station"
FACTION="terran-authority"

def D(x):return x if isinstance(x,dict) else {}
def L(x):return x if isinstance(x,list) else []
def N(x):return float(x) if isinstance(x,(int,float)) and not isinstance(x,bool) else None

def market(report,loc,resource):
    all_markets=[m for m in L(D(report).get("markets"))
                 if D(m).get("facility_location",D(m).get("location"))==loc]
    if len(all_markets)!=1:return {"count":len(all_markets),"stock":None,"demand":None}
    m=all_markets[0]
    return {"count":1,"stock":N(D(m.get("supply")).get(resource)),
            "demand":N(D(m.get("demand")).get(resource))}

def pressure(report,loc,resource):
    m=market(report,loc,resource)
    shortages=[]
    # Real 0.6.2 shortage_ticks lives in MarketPricing API objects,
    # not in facilities. Never infer another location's shortage.
    for market_row in L(D(report).get("markets")):
        if D(market_row).get("facility_location")!=loc:continue
        value=N(D(D(market_row).get("shortage_ticks")).get(resource))
        if value is not None:shortages.append(value)
    st=max(shortages) if shortages else None
    on=bool(st is not None and st>0 or
            m["stock"] is not None and m["demand"] is not None and
            m["demand"]>0 and m["stock"]<m["demand"])
    return dict(m,shortage_ticks=st,pressure=on,
        pressure_kind=("shortage_ticks" if st is not None and st>0 else
        "stock_below_market_demand" if on else None))

def goals(strategy,loc,resource,faction):
    result=[]
    for f in L(D(strategy).get("factions")):
        f=D(f)
        if f.get("faction_id",f.get("id"))!=faction:continue
        for x in L(f.get("goals")):
            x=D(x)
            if x.get("destination",x.get("location"))==loc and x.get("commodity")==resource:
                result.append({"goal_id":x.get("goal_id"),"status":x.get("status")})
    return result

def contract_match(c,loc,resource,faction):
    return (c.get("commodity")==resource and
            c.get("destination_location",c.get("destination"))==loc and
            c.get("faction_id")==faction and
            isinstance(c.get("id"),str) and bool(c["id"]))

def native_market_receipt_qty(record,c,location,commodity):
    """A *native* commit event plus matching immutable contract metadata.

    Genesis standard delivery has no intermediate PickedUp/Delivered status:
    Accepted -> Paid. Engine apply::commit_contract_delivery emits
    contract_delivered AFTER applying quantity to destination market.
    Standard event omits quantity, so recover only the exact quantity of
    the matching native contract ID. Do NOT treat construction materials
    or household food (consumed directly by population) as market inflow.
    """
    event=D(D(record).get("event",record))
    if (event.get("kind")!="contract_delivered"
        or event.get("contract_id")!=c.get("id")
        or event.get("commodity")!=commodity
        or event.get("destination")!=location
        or event.get("contract_type")!=c.get("contract_type")
        or c.get("contract_type") not in ("delivery","subsidy","courier","supply")
        or D(c.get("funding")).get("source") not in ("facility","faction")):
        return None
    qty=N(c.get("quantity"))
    if qty is None or qty<=0:return None
    event_qty=N(event.get("quantity"))
    if event_qty is not None and event_qty!=qty:return None
    return qty


def inventory(samples,events):
    report_keys,strategy_keys,contract_keys,event_keys=set(),set(),set(),set()
    event_kinds=Counter();contract_statuses=set();scoped_paths=set()
    for s in samples:
        report_keys.update(D(s.get("report")).keys())
        strategy_keys.update(D(s.get("strategy")).keys())
        for c in L(s.get("contracts")):
            if isinstance(c,dict):
                contract_keys.update(c.keys())
                contract_statuses.add(str(c.get("status")))
    for row in events:
        e=D(D(row).get("event",row))
        event_keys.update(e.keys())
        event_kinds[str(e.get("kind","unknown"))]+=1
    def scan(obj,prefix,depth=0):
        if depth>5:return
        if isinstance(obj,dict):
            for k,v in list(obj.items())[:100]:
                path=prefix+"."+str(k)
                if any(x in str(k).lower() for x in
                   ("shortage","delivered_units","quantity_delivered",
                    "native_order_id","receipt","stock_delta")):
                    scoped_paths.add(path)
                scan(v,path,depth+1)
        elif isinstance(obj,list) and obj:scan(obj[0],prefix+"[0]",depth+1)
    for s in samples[:3]:scan(s,"sample")
    for e in events[:10]:scan(e,"event")
    return {"samples":len(samples),"event_rows":len(events),
        "report_keys":sorted(report_keys),"strategy_keys":sorted(strategy_keys),
        "contract_keys":sorted(contract_keys),"contract_statuses":sorted(contract_statuses),
        "event_keys":sorted(event_keys),"event_kinds":dict(event_kinds),
        "candidate_proof_paths":sorted(scoped_paths)[:120],
        "station_markets_found":sorted({market(D(s.get("report")),STATION,"food")["count"]
                for s in samples})}

def assess(samples,events,build_sha=None):
    samples=sorted(samples,key=lambda s:int(D(s.get("health")).get(
        "tick",D(s.get("report")).get("tick",0))))
    inv=inventory(samples,events)
    # Identity is read from the actual station in the actual server snapshot.
    owners={D(f).get("faction_id") for s in samples
        for f in L(D(s.get("report")).get("facilities"))
        if D(f).get("type")=="station" and D(f).get("location")==STATION}
    owners.discard(None)
    if len(owners)!=1:
        raise ValueError("Sol S0 station owner missing or unstable: "+str(owners))
    faction=next(iter(owners))
    result={"format":"sol-relief-s0-v1","build_sha":build_sha,
       "world_seed":D(samples[0].get("report")).get("world_seed") if samples else None,
       "fresh_database":True,"faction_id":faction,"station_id":STATION,
       "sample_count":len(samples),"signal_inventory":inv,
       "by_commodity":{},"delivery_verified":False,"relief_verified":"unknown",
       "resilience_verified":"not_tested",
       "conclusion":"measured_not_causally_verified"}
    for item in COMMODITIES:
        x={"t_pressure":None,"pressure_kind":None,"t_goal":None,"goal_id":None,
           "t_funded":None,"t_pickup":None,"t_delivered":None,
           "contract_id":None,"native_order_id":None,"delivered_units":None,
           "delivery_quantity_source":None,"t_paid":None,
           "stock_before":None,"stock_after":None,
           "delivery_verified":False,"relief_verified":"unknown",
           "blockers":[],"market_series":[],"contracts_seen":{},
           "native_goal_last":None,"native_assessments_last":[],
           "head_last":None,"construction_last":None}
        contracts={}
        for s in samples:
            tick=int(D(s.get("health")).get("tick",D(s.get("report")).get("tick",0)))
            report=D(s.get("report"))
            obs=pressure(report,STATION,item)
            x["market_series"].append(dict(tick=tick,**obs))
            if x["t_pressure"] is None and obs["pressure"]:
                x["t_pressure"]=tick
                x["stock_before"]=obs["stock"]
                x["pressure_kind"]=obs["pressure_kind"]
            strat=D(s.get("strategy"))
            gs=goals(strat,STATION,item,faction)
            fv=next((D(f) for f in L(strat.get("factions"))
                     if D(f).get("faction_id")==faction),{})
            x["native_goal_last"]=next((g for g in L(fv.get("goals"))
                if D(g).get("commodity")==item
                and D(g).get("destination")==STATION),None)
            x["native_assessments_last"]=[
                a for a in L(fv.get("assessments"))
                if D(D(a).get("goal")).get("commodity")==item
                and D(D(a).get("goal")).get("destination")==STATION]
            head=D(fv.get("head"))
            if D(head.get("problem")).get("commodity")==item or (
                D(head.get("native_chain_probe")).get("commodity")==item):
                x["head_last"]={"selected_option":head.get("selected_option"),
                   "reason":head.get("reason"),
                   "problem":head.get("problem"),
                   "native_chain_probe":head.get("native_chain_probe")}
            construction=D(fv.get("construction"))
            if D(construction.get("selected_goal")).get("commodity")==item:
                x["construction_last"]={
                   "status":construction.get("status"),
                   "reason":construction.get("reason"),
                   "contract_id":construction.get("contract_id"),
                   "delivery_block_reason":construction.get("delivery_block_reason")}
            if gs and x["t_goal"] is None:
                x["t_goal"]=tick;x["goal_id"]=gs[0]["goal_id"]
            for c in L(s.get("contracts")):
                c=D(c)
                if contract_match(c,STATION,item,faction):
                    contracts.setdefault(c["id"],[]).append((tick,c))
        # Keep the FIRST funded candidate for the backlog report. Prefer
        # a verified physical receipt only if its exact ID, location, cargo
        # and actual native escrow can all be proven. "Paid" alone fails.
        candidates=[]
        for cid,history in sorted(contracts.items()):
            phases=[str(c.get("status","unknown")).lower() for _,c in history]
            x["contracts_seen"][cid]=phases
            funding=next(((t,c) for t,c in history if
                (N(D(c.get("funding")).get("reserved")) or 0)>0),None)
            pickup=next(((t,c) for t,c in history if
                str(c.get("status","")).lower()=="picked_up"),None)
            paid=next(((t,c) for t,c in history if
                str(c.get("status","")).lower()=="paid"),None)
            found=None
            if funding:
                for row in events:
                    t=D(row).get("tick")
                    if not isinstance(t,(int,float)) or t<funding[0]:continue
                    qty=native_market_receipt_qty(row,funding[1],STATION,item)
                    if qty is not None:
                        found=(int(t),qty)
                        break
            candidates.append({"cid":cid,"funding":funding,"pickup":pickup,
                "paid":paid,"receipt":found,
                "native_order_id":D(D(history[0][1].get("funding")).get(
                    "station_order")).get("order_id")})
        chosen=next((v for v in candidates if v["receipt"] is not None),None)
        if chosen is None:
            chosen=next((v for v in candidates if v["funding"] is not None),None)
        if chosen:
            x["contract_id"]=chosen["cid"]
            x["t_funded"]=chosen["funding"][0]
            x["t_pickup"]=chosen["pickup"][0] if chosen["pickup"] else None
            x["t_paid"]=chosen["paid"][0] if chosen["paid"] else None
            x["native_order_id"]=chosen["native_order_id"]
            if chosen["receipt"] is not None:
                x["t_delivered"],x["delivered_units"]=chosen["receipt"]
                x["delivery_quantity_source"]="exact_native_contract_quantity_on_commit_event"
                x["delivery_verified"]=True
        x["stock_after"]=next((v["stock"] for v in reversed(x["market_series"])
            if v["stock"] is not None),None)
        if x["t_pressure"] is None:x["blockers"].append("pressure_not_observed")
        if x["t_goal"] is None:x["blockers"].append("no_matching_goal_in_strategy")
        if x["t_funded"] is None:x["blockers"].append("no_funded_matching_native_contract")
        if x["t_delivered"] is None:x["blockers"].append("no_matching_native_market_delivery_commit_event")
        if x["delivered_units"] is None:x["blockers"].append("no_matching_contract_quantity_and_native_receipt")
        x["blockers"].append("no_verified_causal_background_for_stock_delta")
        result["by_commodity"][item]=x
    result["delivery_verified"]=any(x["delivery_verified"]
        for x in result["by_commodity"].values())
    return result

def read_jsonl(path):
    if not path or not path.is_file():return []
    out=[]
    for l in path.read_text(encoding="utf8").splitlines():
        if l.strip():
            v=json.loads(l)
            if not isinstance(v,dict):raise ValueError("JSONL row must be object")
            out.append(v)
    return out

def write_result(samples,events,out,sha=None):
    out.mkdir(parents=True,exist_ok=True)
    result=assess(samples,events,sha)
    (out/"result.json").write_text(json.dumps(result,indent=2,ensure_ascii=False)+"\n",
        encoding="utf8")
    (out/"signal-inventory.json").write_text(
        json.dumps(result["signal_inventory"],indent=2,ensure_ascii=False)+"\n",
        encoding="utf8")
    lines=["# Living Sector S0 — реальная телеметрия, не Golden-success","",
      f"Сборка: {sha}, seed: {result['world_seed']}, снимков: {len(samples)}","",
      "| Ресурс | pressure | goal | funded | pickup | delivered | delivery verified | relief |",
      "|---|---:|---:|---:|---:|---:|---|---|"]
    for name,x in result["by_commodity"].items():
        fields=[str(x[k]) if x[k] is not None else "—" for k in (
            "t_pressure","t_goal","t_funded","t_pickup","t_delivered")]
        lines.append("| "+" | ".join([name,*fields,
           str(x["delivery_verified"]),str(x["relief_verified"])])+" |")
    lines.extend(["","Результат S0 НЕ доказывает устранение дефицита.",
       "Для green Golden-v1 необходимы подтверждённый native cargo receipt",
       "и измеренный причинный эффект относительно фона.",""])
    for name,x in result["by_commodity"].items():
        lines.append(f"- {name}: "+", ".join(x["blockers"]))
    (out/"REPORT-RU.md").write_text("\n".join(lines)+"\n",encoding="utf8")
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--samples",type=Path,required=True)
    p.add_argument("--events",type=Path)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--build-sha")
    args=p.parse_args()
    result=write_result(read_jsonl(args.samples),read_jsonl(args.events),
        args.output,args.build_sha)
    report=(args.output/"REPORT-RU.md").read_text(encoding="utf8")
    print(report.encode("ascii","backslashreplace").decode("ascii"),flush=True)
    if not result["sample_count"]:raise SystemExit("No real snapshots, S0 invalid")

if __name__=="__main__":main()
