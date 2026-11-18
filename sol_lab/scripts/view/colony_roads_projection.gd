extends RefCounted
## Read-only schematic district links for ANY planetary body.
## Links have real N39 source-backed endpoints; no physical cargo, markets,
## credits, or simulated road networks are fabricated.
const MAX_SURFACE: int = 48 # Per planet, not per entire star system.
const MAX_EXTRA_LINKS: int = 24 # Per planet.
const MAX_PARTICLES_PER_LINK: int = 5
const RECENT_PAID_TICKS: int = 12
const HUB_KEY: String = "@surface-hub"
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
    return clampi(ceili(sqrt(float(workers)) * 1.3),
        1, MAX_PARTICLES_PER_LINK)

static func build(surface: Array, live_status: Dictionary, tick: int) -> Dictionary:
    var sites: Dictionary = {}
    var hubs: Dictionary = {}
    var has_ac: Dictionary = {}
    var bodies: Dictionary = {}
    var types: Dictionary = {}
    var locations: Dictionary = {}
    var activity: Dictionary = {}
    var by_body_count: Dictionary = {}
    var keys: Array[String] = []
    for asset in surface:
        if not (asset is Dictionary):
            continue
        var id: String = str(asset.get("id", ""))
        var bid: String = str(asset.get("body", ""))
        var site: Variant = asset.get("site", null)
        if id.is_empty() or bid.is_empty() or sites.has(id) or (
                not (site is Vector2)):
            continue
        var used: int = int(by_body_count.get(bid, 0))
        if used >= MAX_SURFACE:
            continue
        by_body_count[bid] = used + 1
        keys.append(id)
        sites[id] = site
        types[id] = str(asset.get("render_type", asset.get("type", "")))
        locations[id] = str(asset.get("location", ""))
        bodies[id] = bid
        activity[id] = _activity(live_status.get(id, {}), tick)
        if not hubs.has(bid):
            hubs[bid] = asset.get("hub_site", HUB_SITE)
        if types[id] == "administrative_center":
            hubs[bid] = site
            has_ac[bid] = true
    keys.sort()
    for bid in hubs:
        sites[HUB_KEY + ":" + str(bid)] = hubs[bid]
    if sites.is_empty():
        # Preserve the empty no-colony seed contract, with zero links.
        sites[HUB_KEY] = HUB_SITE
    var links: Array[Dictionary] = []
    var groups: Dictionary = {}
    for id in keys:
        var body_id: String = bodies[id]
        if not (has_ac.has(body_id) and
                types[id] == "administrative_center"):
            links.append({
                "a": HUB_KEY + ":" + body_id, "b": id,
                "kind": "access", "body": body_id,
                "particles": activity[id]
            })
        var g: String = body_id + "|" + locations[id]
        if not groups.has(g):
            groups[g] = {"mine": [], "ref": [], "factory": [],
                "body": body_id}
        if types[id] == "mining_rig":
            groups[g]["mine"].append(id)
        elif types[id] == "refinery":
            groups[g]["ref"].append(id)
        elif types[id] == "factory":
            groups[g]["factory"].append(id)
    # Scope chain edges to the SAME body+location group. The previous
    # all-pairs loop could cost O(N²) when procedural systems grow.
    var used_extra: Dictionary = {}
    for g in groups:
        var members: Dictionary = groups[g]
        var bid: String = str(members["body"])
        var used: int = int(used_extra.get(bid, 0))
        for pairing in [
                [members["mine"], members["ref"]],
                [members["ref"], members["factory"]]]:
            for src in pairing[0]:
                if used >= MAX_EXTRA_LINKS:
                    break
                for dst in pairing[1]:
                    if used >= MAX_EXTRA_LINKS:
                        break
                    links.append({
                        "a": src, "b": dst,
                        "kind": "production", "body": bid,
                        "particles": mini(activity[src], activity[dst])
                    })
                    used += 1
        used_extra[bid] = used
    return {"sites": sites, "links": links, "hubs": hubs,
        "has_ac": has_ac}
