extends RefCounted
## N44: pure, read-only projection of frozen Rust Director/ResearchMandate rules.
## Does not authorize paid ECS transfers, add technology, or mutate treasury.
## Sources: native/crates/sim_core/src/strategy/{director,governance,progression}.rs
const TECHNOLOGIES: Array[Dictionary] = [
    {"id":"industrial_methods","prerequisite":"","work":40,"field":"industry"},
    {"id":"orbital_habitats","prerequisite":"","work":50,"field":"expansion"},
    {"id":"deep_navigation","prerequisite":"orbital_habitats","work":70,"field":"expansion"},
    {"id":"automation","prerequisite":"industrial_methods","work":90,"field":"industry"},
    {"id":"alloytech2","prerequisite":"automation","work":110,"field":"industry"},
    {"id":"survey2","prerequisite":"deep_navigation","work":110,"field":"science"},
    {"id":"drilltech2","prerequisite":"alloytech2","work":120,"field":"industry"},
    {"id":"structuretech2","prerequisite":"alloytech2","work":160,"field":"industry"},
    {"id":"survey3","prerequisite":"survey2","work":160,"field":"science"},
    {"id":"drill3","prerequisite":"drilltech2","work":180,"field":"industry"},
    {"id":"quantumtech3","prerequisite":"structuretech2","work":220,"field":"science"},
    {"id":"structuretech3","prerequisite":"quantumtech3","work":250,"field":"industry"}
]
const TIER_CAPACITY: Dictionary = {"t1":4,"t2":5,"t3":6}
const TIER_GATE: Dictionary = {"t2":"structuretech2","t3":"structuretech3"}
const TIER_NEXT: Dictionary = {"t1":"t2","t2":"t3"}

func technology(id: String) -> Dictionary:
    for entry in TECHNOLOGIES:
        if entry["id"] == id:
            return entry.duplicate(true)
    return {}

func next_technology(target: String, completed: Array) -> Dictionary:
    var current := target
    var seen: Dictionary = {}
    for _i in range(TECHNOLOGIES.size()):
        var item := technology(current)
        if item.is_empty():
            return {"ok":false,"reason":"unknown_technology" if current == target else "invalid_technology_graph"}
        if seen.has(current):
            return {"ok":false,"reason":"technology_dependency_cycle"}
        seen[current] = true
        if completed.has(current):
            return {"ok":true,"next":""}
        var prerequisite: String = item["prerequisite"]
        if prerequisite != "" and not completed.has(prerequisite):
            current = prerequisite
            continue
        return {"ok":true,"next":current,"work":item["work"],"field":item["field"]}
    return {"ok":false,"reason":"technology_dependency_cycle"}

func mandate_valid(target: String, budget: int, floor_cr: int, spent: int) -> String:
    if budget < 100 or budget > 1000000000:
        return "invalid_mandate_budget"
    if floor_cr < 10000 or floor_cr > 1000000000:
        return "invalid_treasury_floor"
    if technology(target).is_empty():
        return "unknown_technology"
    if spent < 0 or spent > budget:
        return "invalid_committed_amount"
    return ""

func spending_gate(budget: int, floor_cr: int, spent: int, cost: int, treasury: int) -> String:
    if cost <= 0:
        return "invalid_research_charge"
    if spent < 0 or cost > budget - spent:
        return "player_mandate_budget_exhausted"
    if cost > treasury or treasury - cost < floor_cr:
        return "player_mandate_treasury_floor"
    return ""

func tier_upgrade_gate(current: String, target: String, completed: Array) -> bool:
    return TIER_NEXT.get(current, "") == target and completed.has(TIER_GATE.get(target, "__missing__"))

func slot_availability(tier: String, built: int, in_progress: int) -> Dictionary:
    if not TIER_CAPACITY.has(tier) or built < 0 or in_progress < 0:
        return {"ok":false,"reason":"invalid_counts"}
    var capacity: int = TIER_CAPACITY[tier]
    var remaining: int = capacity - built - in_progress
    return {"ok":remaining > 0,"remaining":maxi(remaining,0),"capacity":capacity}
