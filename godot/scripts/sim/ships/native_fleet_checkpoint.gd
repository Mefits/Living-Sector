extends RefCounted
## N54: ALL-OR-NOTHING in-memory checkpoint for the *currently implemented*
## bodies+ships slice, N11 ship accounts and N21 docking. No FileAccess.
## Explicitly reject any new mutable simulation phase not in this schema.
## This does NOT save N39 production, contracts, station inventories or AI.
const Runner = preload("res://scripts/sim/ship_tick_runner.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Docking = preload("res://scripts/sim/ships/docking_registry.gd")
const FORMAT: String = "living-sector-fleet-checkpoint"
const VERSION: int = 1

static func capture(runner: RefCounted, ledger: RefCounted,
        dock: RefCounted) -> Dictionary:
    if runner == null or ledger == null or dock == null:
        return _error("missing_authority")
    if not ledger.has_method("snapshot") or not dock.has_method("snapshot"):
        return _error("wrong_account_or_docking_authority")
    if not runner.has_method("orbital_checkpoint_for_fleet_envelope") or not runner.has_method("transit_cursor_for_fleet_envelope"):
        return _error("wrong_runner")
    if runner.implemented_phases() != PackedStringArray(["bodies", "ships"]):
        return _error("unrepresented_mutable_phases")
    var orbital: Dictionary = runner.orbital_checkpoint_for_fleet_envelope()
    var fleet: Array = runner.live_fleet_snapshot()
    var transit_token: int = runner.transit_cursor_for_fleet_envelope()
    var wallet: Dictionary = ledger.snapshot()
    var docking: Dictionary = dock.snapshot()
    if orbital.is_empty() or fleet.is_empty() or transit_token < 1:
        return _error("incomplete_simulation")
    if not _consistent(fleet, wallet, docking):
        return _error("cross_domain_mismatch")
    var payload: Dictionary = {
        "format": FORMAT, "version": VERSION,
        "scope": "native_bodies_ships_credits_docking_only",
        "seed_fingerprint": str(orbital.get("seed_fingerprint", "")),
        "orbital": orbital, "ship_state": fleet,
        "ship_transit_next_token": transit_token,
        "ledger": wallet, "docking": docking
    }
    # Serialize/parse to a JSON-normalized object before hashing. This
    # matches N38's canonical hash principle (not an authentication MAC).
    var normalized: Variant = JSON.parse_string(JSON.stringify(payload))
    if not (normalized is Dictionary):
        return _error("json_not_roundtrippable")
    return {"ok": true, "payload": normalized,
        "sha256": _canonical(normalized).sha256_text()}

## Restore into newly staged authorities. The caller's current runner,
## real ship balances and user save files are NEVER mutated on failure.
## An explicit caller must atomically replace the old world reference if
## and only if result.ok, rather than restoring domains in place.
static func stage_restore(envelope: Dictionary, seed: Dictionary) -> Dictionary:
    var payload_value: Variant = envelope.get("payload", null)
    var digest: Variant = envelope.get("sha256", null)
    if not (payload_value is Dictionary) or not (digest is String) or digest.length() != 64:
        return _error("invalid_envelope")
    var payload: Dictionary = payload_value
    if _canonical(payload).sha256_text() != digest:
        return _error("checksum_mismatch")
    if payload.get("format", "") != FORMAT or payload.get("version", -1) != VERSION:
        return _error("unsupported_schema")
    if payload.get("scope", "") != "native_bodies_ships_credits_docking_only":
        return _error("unsupported_phase_scope")
    for field in ["orbital", "ledger", "docking"]:
        if not (payload.get(field, null) is Dictionary):
            return _error("missing_domain_" + field)
    if not (payload.get("ship_state", null) is Array):
        return _error("missing_fleet")
    var cursor: Variant = payload.get("ship_transit_next_token", null)
    if not (cursor is int or cursor is float) or not is_finite(float(cursor)) or float(cursor) < 1.0 or float(int(cursor)) != float(cursor):
        return _error("invalid_transit_nonce")
    var typed: Dictionary = _restore_exact_integer_fields(payload)
    if typed.is_empty():
        return _error("invalid_integer_payload")
    var fresh = Runner.new()
    if not fresh.start_from_seed(seed):
        return _error("invalid_frozen_seed")
    if str(payload.get("seed_fingerprint", "")) != fresh.world.seed_fingerprint():
        return _error("seed_mismatch")
    if not fresh.restore_checkpoint(typed["orbital"], seed):
        return _error("invalid_orbital_state")
    var staged_fleet = ShipState.new()
    if not staged_fleet.restore(typed["ship_state"]):
        return _error("invalid_ship_state")
    if not fresh.attach_restored_native_fleet(seed, staged_fleet, int(cursor)):
        return _error("ship_transit_or_provenance_rejected")
    var staged_ledger = Ledger.new()
    if not staged_ledger.restore(typed["ledger"]):
        return _error("invalid_credit_ledger")
    var staged_dock = Docking.new()
    if not staged_dock.restore(typed["docking"]):
        return _error("invalid_docking")
    if not _consistent(staged_fleet.snapshot(), staged_ledger.snapshot(), staged_dock.snapshot()):
        return _error("restore_cross_domain_mismatch")
    # All staging succeeded. No original reference was ever modified.
    return {
        "ok": true, "runner": fresh, "ledger": staged_ledger,
        "docking": staged_dock, "tick": fresh.tick_count
    }

## No missing or phantom ship wallets; ship and docking location must agree.
## Ledger also needs at least one externally sourced non-ship account;
## otherwise the user would mistake an incomplete ship-only ledger for the
## whole world's money supply.
static func _consistent(fleet: Array, wallet: Dictionary,
        docking: Dictionary) -> bool:
    if not (wallet.get("balances", null) is Dictionary) or not (docking.get("ships", null) is Dictionary):
        return false
    var balances: Dictionary = wallet["balances"]
    var dock_ships: Dictionary = docking["ships"]
    var ids: Dictionary = {}
    for value in fleet:
        if not (value is Dictionary):
            return false
        var ship: Dictionary = value
        var id: String = str(ship.get("id", ""))
        if id.is_empty() or ids.has(id) or not dock_ships.has(id) or not balances.has("ship:" + id):
            return false
        ids[id] = true
        var dock_record: Variant = dock_ships[id]
        if not (dock_record is Dictionary):
            return false
        var station: Dictionary = dock_record
        var transit: Variant = ship.get("transit", null)
        if not (transit is Dictionary):
            return false
        if (transit as Dictionary).is_empty():
            if bool(station.get("in_transit", true)) or str(station.get("location", "")) != str(ship.get("location", "")):
                return false
        else:
            if not bool(station.get("in_transit", false)) or not str(station.get("location", "")).is_empty() or not str(station.get("docked_at", "")).is_empty():
                return false
        if typeof(balances["ship:" + id]) != TYPE_INT and typeof(balances["ship:" + id]) != TYPE_FLOAT:
            return false
        if float(balances["ship:" + id]) < 0.0:
            return false
    if ids.is_empty() or dock_ships.size() != ids.size():
        return false
    var has_other_world_account: bool = false
    for key in balances:
        var account: String = str(key)
        if account.begins_with("ship:"):
            if not ids.has(account.substr(5)):
                return false
        else:
            has_other_world_account = true
    return has_other_world_account

## Godot JSON may parse integer credit/cargo/nonce fields as floats.
## Restore the exact integer types AFTER checksum validation and only when
## within IEEE-754 safe integer range, never silently round a save value.
static func _restore_exact_integer_fields(payload: Dictionary) -> Dictionary:
    var result: Dictionary = payload.duplicate(true)
    var balances: Dictionary = result["ledger"]["balances"]
    for id in balances:
        var amount: Variant = balances[id]
        if not _safe_json_integer(amount) or float(amount) < 0.0:
            return {}
        balances[id] = int(amount)
    var receipts: Dictionary = result["ledger"]["receipts"]
    for id in receipts:
        var receipt: Dictionary = receipts[id]
        if receipt.has("tick"):
            if not _safe_json_integer(receipt["tick"]):
                return {}
            receipt["tick"] = int(receipt["tick"])
        for leg in receipt.get("legs", []):
            if not (leg is Dictionary) or not _safe_json_integer(leg.get("delta", null)):
                return {}
            leg["delta"] = int(leg["delta"])
    var facilities: Dictionary = result["docking"]["facilities"]
    for id in facilities:
        var facility: Dictionary = facilities[id]
        var capacity: Variant = facility.get("capacity", null)
        if not _safe_json_integer(capacity) or float(capacity) < 0.0:
            return {}
        facility["capacity"] = int(capacity)
    for ship_value in result["ship_state"]:
        if not (ship_value is Dictionary):
            return {}
        var ship: Dictionary = ship_value
        for key in ["cargo_capacity", "crew_size"]:
            if not _safe_json_integer(ship.get(key, null)) or float(ship[key]) < 0.0:
                return {}
            ship[key] = int(ship[key])
        var cargo: Variant = ship.get("cargo", null)
        if not (cargo is Dictionary):
            return {}
        for commodity in cargo:
            if not _safe_json_integer(cargo[commodity]) or float(cargo[commodity]) < 0.0:
                return {}
            cargo[commodity] = int(cargo[commodity])
        var transit: Variant = ship.get("transit", null)
        if not (transit is Dictionary):
            return {}
        for key in ["token", "departure_tick", "last_tick", "arrival_tick"]:
            if not transit.is_empty():
                if not _safe_json_integer(transit.get(key, null)):
                    return {}
                transit[key] = int(transit[key])
    return result

static func _safe_json_integer(value: Variant) -> bool:
    if not (value is int or value is float) or not is_finite(float(value)):
        return false
    return absf(float(value)) <= 9007199254740991.0 and float(int(value)) == float(value)

static func _canonical(value: Variant) -> String:
    if value is Dictionary:
        var keys: Array = value.keys()
        keys.sort()
        var items: PackedStringArray = PackedStringArray()
        for key in keys:
            items.append(JSON.stringify(str(key)) + ":" + _canonical(value[key]))
        return "{" + ",".join(items) + "}"
    if value is Array:
        var items: PackedStringArray = PackedStringArray()
        for item in value:
            items.append(_canonical(item))
        return "[" + ",".join(items) + "]"
    return JSON.stringify(value)

static func _error(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
