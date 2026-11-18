extends RefCounted
## Russian presentation names ONLY. Never localize stored type keys,
## source IDs, facility names in N39, logistics locations, or save data.

const TYPES_RU: Dictionary = {
    "station": "Орбитальная станция",
    "shipyard": "Верфь",
    "mining_rig": "Добывающий комплекс",
    "refinery": "Перерабатывающий комплекс",
    "farm": "Ферма",
    "factory": "Промышленный комплекс",
    "laboratory": "Лаборатория",
    "research": "Исследовательский центр",
    "power_plant": "Электростанция",
    "outpost": "Аванпост",
    "gate": "Звёздные врата",
    "construction_dock": "Строительный док"
}

static func type_name(kind: String) -> String:
    # Unknown source types stay visible rather than being silently hidden.
    return str(TYPES_RU.get(kind, kind))

## WorldModel seed objects and new N151 N39 entries share the same
## presentation rule. Do NOT convert N39 "station" to a new save type here.
static func context_type_name(facility: Dictionary) -> String:
    var kind: String = str(facility.get("type", ""))
    var body_id: String = str(facility.get(
        "body_id", facility.get("body", "")))
    var location: String = str(facility.get("location", ""))
    if not body_id.is_empty() and location == body_id + "-colony":
        if kind == "station":
            return "Административный центр"
        if kind == "construction_dock":
            return "Строительный док колонии"
    return type_name(kind)

static func display_name(facility: Dictionary) -> String:
    var kind: String = str(facility.get("type", ""))
    if TYPES_RU.has(kind):
        return context_type_name(facility)
    return str(facility.get("name", kind))
