extends RefCounted
## UI-only Sol surface road projection from the existing SystemBalance assets.
## No new N39 facility/site/physical transport/credits or world snapshots.
## Links represent possible shared-location economic relations, NOT cargo.
const MAX_SURFACE: int = 48
const MAX_EXTRA_LINKS: int = 24
const MAX_PARTICLES_PER_LINK: int = 5
const RECENT_PAID_TICKS: int = 12
const HUB_KEY: String = "@surface-hub"
## Styled location on the existing Earth land polygon; not a real AC facility.
const HUB_SITE: Vector2 = Vector2(-0.30, -0.22)

static func _activity(status: Dictionary, tick: int) -> int:
    if not bool(status.get("present", false)):
        return 0
    var paid_tick: int = int(status.get("shift_tick", -1))
    if paid_tick < 0 or tick < paid_tick or tick - paid_tick > RECENT_PAID_TICKS:
        return 0
    var workers: int = maxi(0, int(status.get("shift_workers", 0)))
    if workers <= 0:
        return 0
    return clampi(ceili(sqrt(float(workers)) * 1.3), 1,
        MAX_PARTICLES_PER_LINK)

static func build(surface: Array, live_status: Dictionary, tick: int) -> Dictionary:
    # Keep only real, source-backed surface IDs and their given schematic
    # sites; do not compute a second geography, location or facility roster.
    var sites: Dictionary = {}
    var hubs: Dictionary = {}
    var has_ac: Dictionary = {}
    # One access junction per real planetary body, never one global road
    # network joining separate planets. It is presentation-only.
    for asset in surface:
        if not (asset is Dictionary):
            continue
        var body_id: String = str(asset.get("body", ""))
        if body_id.is_empty():
            continue
        if not hubs.has(body_id):
            hubs[body_id] = asset.get("hub_site", HUB_SITE)
        if str(asset.get("render_type", "")) == "administrative_center":
            hubs[body_id] = asset.get("site", HUB_SITE)
            has_ac[body_id] = true
    for body_id in hubs:
        sites[HUB_KEY + ":" + str(body_id)] = hubs[body_id]
    if sites.is_empty():
        sites[HUB_KEY] = HUB_SITE
    var types: Dictionary = {}
    var locations: Dictionary = {}
    var bodies: Dictionary = {}
    var activity: Dictionary = {}
    var keys: Array[String] = []
    for asset in surface:
        if not (asset is Dictionary):
            continue
        var id: String = str(asset.get("id", ""))
        if id.is_empty() or sites.has(id) or not (asset.get("site") is Vector2):
            continue
        if keys.size() >= MAX_SURFACE:
            break
        keys.append(id)
        sites[id] = asset["site"]
        types[id] = str(asset.get("render_type", asset.get("type", "")))
        locations[id] = str(asset.get("location", ""))
        bodies[id] = str(asset.get("body", ""))
        activity[id] = _activity(live_status.get(id, {}), tick)
    keys.sort()
    var links: Array[Dictionary] = []
    for id in keys:
        # The administrative center itself is the junction on founded
        # colonies; do not draw a fictitious second AC or a zero-length road.
        if has_ac.has(bodies[id]) and (
                types[id] == "administrative_center"):
            continue
        links.append({"a": HUB_KEY + ":" + bodies[id], "b": id,
            "kind": "access", "body": bodies[id],
            "particles": activity[id]})
    var extras: int = 0
    for source in keys:
        if extras >= MAX_EXTRA_LINKS:
            break
        for target in keys:
            if extras >= MAX_EXTRA_LINKS:
                break
            if source == target or locations[source] != locations[target] or (
                    bodies[source] != bodies[target]):
                continue
            var chain: bool = (
                (types[source] == "mining_rig" and types[target] == "refinery")
                or (types[source] == "refinery" and types[target] == "factory"))
            if not chain:
                continue
            links.append({"a": source, "b": target, "kind": "production",
                "body": bodies[source],
                "particles": mini(activity[source], activity[target])})
            extras += 1
    return {"sites": sites, "links": links, "hubs": hubs,
        "has_ac": has_ac}
