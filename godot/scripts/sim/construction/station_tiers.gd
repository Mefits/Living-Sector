extends RefCounted
## Native strategy/progression.rs: pure station-tier and occupied-slot gates.
## Research is a prerequisite, never a construction receipt or free upgrade.

const CAPACITY: Dictionary = {"t1": 4, "t2": 5, "t3": 6}
const NEXT: Dictionary = {"t1": "t2", "t2": "t3"}
const GATE: Dictionary = {"t2": "structuretech2", "t3": "structuretech3"}
const MATERIAL_BILLS: Dictionary = {
    "t2": {"metals": 240, "components": 100, "alloys": 40},
    "t3": {"alloys": 160, "electronics": 80, "quantum_cores": 36}
}
const WORK: Dictionary = {"t2": 150, "t3": 250}

static func available_slots(tier: String, built: int, in_progress: int) -> int:
    if not CAPACITY.has(tier) or built < 0 or in_progress < 0:
        return -1
    if built > 1000000 or in_progress > 1000000:
        return -1
    return maxi(0, int(CAPACITY[tier]) - built - in_progress)

static func upgrade_research_ready(current: String, target: String, completed: Array) -> bool:
    return NEXT.get(current, "") == target and completed.has(GATE.get(target, ""))

static func native_upgrade_bill(target: String) -> Dictionary:
    return MATERIAL_BILLS.get(target, {}).duplicate(true)

static func upgrade_work(target: String) -> int:
    return int(WORK.get(target, 0))
