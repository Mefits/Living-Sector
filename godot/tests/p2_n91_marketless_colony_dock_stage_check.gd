extends SceneTree
## Pure N91 receipt-guard regression. The fixtures cannot move ships or
## change N9/N15; integrated 420-tick acceptance separately tests live World.
const N91 = preload("res://scripts/sim/phase2/unified_n91_construction_dispatch.gd")

func _initialize() -> void:
    var sid: String = "source-colony-site"
    var loc: String = "source-body-colony"
    var faction: String = "source-faction"
    var fid: String = "source-temporary-dock"
    var site: Dictionary = {
        "id": sid, "location_name": loc, "faction_id": faction,
        "labor": {"colony_source": "source-home-station"},
        "progress_delivered": 0, "progress_required": 600,
        "completed": false}
    var world: Dictionary = {"construction_sites": {sid: site},
        "construction_receipts": {}, "facilities": {}, "markets": {}, "ships": {}}
    if N91.physical_site_dock(world, sid).get("ok", false):
        _fail("unreceipted marketless location became an engineer dock")
        return
    if N91.physical_site_funded(world, {"receipts": {}}, sid):
        _fail("unpaid N151 colony was admitted for construction")
        return
    world["facilities"][fid] = {
        "type": "construction_dock", "construction_source_site_id": sid,
        "location": loc, "faction": faction, "docking_capacity": 4,
        "abandoned": false}
    world["construction_receipts"]["n151_colony_dock:" + sid] = {
        "id": "n151_colony_dock:" + sid, "kind": "colony_dock_prepared",
        "site_id": sid, "destination_location": loc,
        "faction_id": faction, "facility_id": fid}
    var proved: Dictionary = N91.physical_site_dock(world, sid)
    if not proved.get("ok", false) or proved.get("facility_id") != fid or proved.get("type") != "construction_dock":
        _fail("real N151 construction dock receipt not recognized")
        return
    # A forged/incorrect receipt cannot authorize the alternate N21 dock.
    world["construction_receipts"]["n151_colony_dock:" + sid]["faction_id"] = "other"
    if N91.physical_site_dock(world, sid).get("ok", false):
        _fail("wrong-faction N151 receipt authorized an engineer")
        return
    world["construction_receipts"]["n151_colony_dock:" + sid]["faction_id"] = faction
    world["construction_sites"][sid]["labor"]["colony_source"] = null
    if N91.physical_site_dock(world, sid).get("ok", false):
        _fail("ordinary industrial site bypassed genuine station-market check")
        return
    print("P2_N91_SOURCE_N151_MARKETLESS_RECEIPTED_DOCK_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_N91_COLONY_DOCK_GUARD_FAIL: " + message)
    quit(1)
