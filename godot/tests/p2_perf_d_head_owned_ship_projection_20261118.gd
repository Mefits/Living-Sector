extends SceneTree
## Exact old two-pass Head capture oracle: sorted owned ships and contracts.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _legacy_ships(world: Dictionary, faction: String) -> Array:
    var ids: Array = []
    for sid in world["ships"]:
        if str(world["ships"][sid].get("faction_id", "")) == faction:
            ids.append(sid)
    ids.sort()
    var out: Array = []
    for sid in ids:
        var ship: Dictionary = world["ships"][sid]
        var cargo_total: int = 0
        for amount in ship.get("cargo", {}).values():
            assert(typeof(amount) == TYPE_INT and int(amount) >= 0)
            cargo_total += int(amount)
        out.append({"ship_id": str(sid), "class": str(ship.get("class", "")),
            "location_id": ship.get("location", null) if ship.get(
                "transit", {}).is_empty() else null,
            "in_transit": not ship.get("transit", {}).is_empty(),
            "free_cargo": maxi(0, int(ship.get("cargo_capacity", 0)) - cargo_total),
            "fuel": float(ship.get("fuel", 0.0))})
    return out

func _legacy_contracts(world: Dictionary, faction: String) -> Array:
    var ids: Array = world["contract_board"]["contracts"].keys()
    ids.sort()
    var out: Array = []
    for cid in ids:
        var c: Dictionary = world["contract_board"]["contracts"][cid]
        var status: String = str(c.get("status", "")).to_lower()
        if status in ["paid", "expired"]:
            continue
        if str(c.get("requestor_id", "")) != faction and str(c.get(
                "requestor_id", "")) != "faction/" + faction and str(c.get(
                "faction_id", "")) != faction:
            continue
        out.append({"contract_id": str(cid), "status": status,
            "source": str(c.get("source_location", "")),
            "destination": str(c.get("destination_location", "")),
            "commodity": str(c.get("commodity", "")),
            "quantity": int(c.get("quantity", 0)),
            "assigned_ship_id": c.get("fulfiller_id", null)})
    return out

func _check(world: Dictionary, tick: int) -> void:
    var before: Dictionary = world.duplicate(true)
    var captured: Dictionary = Head.capture(world, "alpha", tick)
    assert(captured.get("ok", false), "valid capture rejected")
    var snap: Dictionary = captured["snapshot"]
    assert(snap["ships"] == _legacy_ships(world, "alpha"),
        "ship DTO/order differs from original two-pass projection")
    assert(snap["active_commitments"] == _legacy_contracts(world, "alpha"),
        "contract DTO/order differs from original sorted board projection")
    assert(world == before, "capture mutated authoritative World")
    if not snap["ships"].is_empty():
        snap["ships"][0]["fuel"] = -123.0
        assert(world == before, "captured ship aliases World")

func _initialize() -> void:
    var world: Dictionary = {"faction_treasuries": {"alpha": 9000},
        "facilities": {}, "markets": {}, "ships": {}, "populations": {},
        "contract_board": {"contracts": {}}, "research": {"alpha": []}}
    for i in range(180):
        var sid: String = "ship_%03d" % i
        world["ships"][sid] = {"faction_id": "alpha" if i % 4 == 0 else "beta",
            "class": "freighter", "cargo": {"ore": i % 7, "water": i % 3},
            "cargo_capacity": 20, "location": "sol",
            "transit": {"to": "mars"} if i % 5 == 0 else {},
            "fuel": float(i)}
        var cid: String = "contract_%03d" % i
        world["contract_board"]["contracts"][cid] = {
            "requestor_id": "faction/alpha" if i % 3 == 0 else "beta",
            "faction_id": "alpha" if i % 11 == 0 else "beta",
            "status": "PAID" if i % 7 == 0 else "Open",
            "source_location": "sol", "destination_location": "mars",
            "commodity": "ore", "quantity": i, "fulfiller_id": sid}
    _check(world, 10)
    world["ships"]["ship_000"]["faction_id"] = "beta"
    world["ships"]["ship_001"]["faction_id"] = "alpha"
    world["contract_board"]["contracts"]["contract_003"]["faction_id"] = "beta"
    world["contract_board"]["contracts"]["contract_003"]["requestor_id"] = "beta"
    world["contract_board"]["contracts"]["contract_004"]["faction_id"] = "alpha"
    world["contract_board"]["contracts"]["contract_004"]["status"] = "OPEN"
    _check(world, 11)
    world["ships"]["ship_001"]["cargo"]["ore"] = -1
    var invalid: Dictionary = Head.capture(world, "alpha", 12)
    assert(not invalid.get("ok", true), "negative cargo was accepted")
    assert(invalid.get("reason") == "n100_invalid_original_cargo",
        "cargo rejection changed")
    world["ships"]["ship_001"]["cargo"]["ore"] = 0
    _check(world, 13)
    print("PASS p2_perf_d_head_owned_ship_projection_20261118")
    quit(0)
