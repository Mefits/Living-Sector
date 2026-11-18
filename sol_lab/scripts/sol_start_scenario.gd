extends RefCounted
## Sol Lab starter scenario. Transforms a detached copy of the frozen Sol
## seed; no changes to SystemBalance or res://data/sol.json.
const OLD_LOCATION: String = "earth-station"
const AC_LOCATION: String = "earth-colony"
const AC_ID: String = "facility-earth-administrative-center"
const Model = preload("res://scripts/sol_building_model.gd")

static func apply(source: Dictionary) -> Dictionary:
    var world: Dictionary = source.duplicate(true)
    if str(world.get("system", {}).get("id", "")) != "system-sol":
        return world
    var old_station: Dictionary = {}
    var remaining: Array = []
    for item in world.get("facilities", []):
        if not (item is Dictionary):
            continue
        if str(item.get("body", "")) == "earth":
            if str(item.get("location", "")) == OLD_LOCATION and (
                    str(item.get("type", "")) == "station"):
                old_station = item.duplicate(true)
            continue
        remaining.append(item.duplicate(true))
    if old_station.is_empty():
        push_error("Sol Lab start: Earth source station missing; not applying scenario")
        return world
    # Retain the old station's actual storage/services/docking metadata.
    # In the original SystemBalance physical-assets projection,
    # 'station' at 'earth-colony' is rendered as a GROUND AC.
    old_station["id"] = AC_ID
    old_station["name"] = "Административный центр"
    old_station["location"] = AC_LOCATION
    old_station["body"] = "earth"
    old_station["surface_site"] = Model.surface_site("administrative_center")
    remaining.append(old_station)
    world["facilities"] = remaining

    # No free storage or new resource amounts are invented:
    # existing seeded inventory, population, ships and routes follow
    # the new AC location without orphaning 'earth-station' references.
    for collection in ["markets", "populations", "ships", "travel_routes"]:
        var updated: Array = []
        for item in world.get(collection, []):
            if not (item is Dictionary):
                updated.append(item)
                continue
            var entry: Dictionary = item.duplicate(true)
            for field in ["facility_id", "location", "from", "to"]:
                if str(entry.get(field, "")) == OLD_LOCATION:
                    entry[field] = AC_LOCATION
            if collection == "markets" and str(entry.get("id", "")) == (
                    "market-earth-station"):
                entry["id"] = "market-earth-colony"
            if collection == "populations" and str(entry.get(
                    "label", "")) == "Residents earth-station":
                entry["label"] = "Residents earth-colony"
            updated.append(entry)
        world[collection] = updated
    return world
