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

static func display_name(facility: Dictionary) -> String:
    var kind: String = str(facility.get("type", ""))
    if TYPES_RU.has(kind):
        return type_name(kind)
    return str(facility.get("name", kind))
