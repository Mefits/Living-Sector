extends RefCounted
## N108 Phase-1 independent dispatcher for three distinct frozen Rust
## SimCommand::RequestGateJump / RequestRefit / ReleaseContract branches.
## This is an exclusive transaction PREVIEW over a detached world.
## Future Phase-2 SimCommand dispatcher owns once-only receipt/application;
## do not allow this module to create a second economic clock or ledger.
const Gate = preload("res://scripts/port/n108_gate_jump_apply.gd")
const Refit = preload("res://scripts/port/n108_shipyard_refit_apply.gd")
const Breach = preload("res://scripts/port/n108_contract_breach_apply.gd")

## Native commands: 
## {"kind":"gate_jump", "ship_id", "source", "destination"}
## {"kind":"agent_refit"|"admin_shipyard_refit"|"admin_override_refit",
##       "ship_id","slot","slug":string|null}
## {"kind":"release_contract", "ship_id","contract_id","reason","tick"}
## All values come from trusted SimCommand / authenticated admin endpoint.
static func apply(world: Dictionary, command: Dictionary) -> Dictionary:
    var kind: String = str(command.get("kind", ""))
    var ship_id: String = str(command.get("ship_id", ""))
    if ship_id.is_empty():
        return _reject("missing_ship_id")
    match kind:
        "gate_jump":
            return Gate.apply(world, ship_id,
                str(command.get("source", "")),
                str(command.get("destination", "")))
        "agent_refit":
            return Refit.agent_refit(world, ship_id,
                str(command.get("slot", "")),
                str(command.get("slug", "")))
        "admin_shipyard_refit":
            if not bool(command.get("authenticated_admin", false)):
                return _reject("admin_authorization_required")
            return Refit.admin_shipyard(world, ship_id,
                str(command.get("slot", "")),
                str(command.get("slug", "")))
        "admin_override_refit":
            if not bool(command.get("authenticated_admin", false)):
                return _reject("admin_authorization_required")
            return Refit.admin_override(world, ship_id,
                str(command.get("slot", "")), command.get("slug", null))
        "release_contract":
            return Breach.apply(world, ship_id,
                str(command.get("contract_id", "")),
                str(command.get("reason", "")),
                int(command.get("tick", -1)))
        _:
            return _reject("unknown_special_command")

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason, "events": []}
