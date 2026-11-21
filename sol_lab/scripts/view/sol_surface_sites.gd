extends RefCounted
## One editable source of stable surface-site IDs and port pads. Coordinates
## are local to the visible artwork disc: (0,0)=centre, +/-1=globe edge.
## No ship landing or physical container logic is implemented here.
const SOURCE = "res://data/sol_surface_sites.json"
static var _cached: Dictionary = {}

static func layout() -> Dictionary:
 if _cached.is_empty():
  var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
  if value is Dictionary:
   _cached = value
 return _cached

static func entries(body: String, building_id: String = "") -> Array:
 var result: Array = []
 for raw in layout().get(body, []):
  if not (raw is Dictionary):
   continue
  if not building_id.is_empty() and building_id not in raw.get("types", []):
   continue
  result.append(raw)
 return result

static func get_site(body: String, site_id: String) -> Dictionary:
 for entry in entries(body):
  if str(entry.get("id", "")) == site_id:
   return entry
 return {}

static func site_position(site: Dictionary) -> Vector2:
 var xy: Variant = site.get("at", [])
 if not (xy is Array) or xy.size() != 2:
  return Vector2.ZERO
 return Vector2(float(xy[0]), float(xy[1]))

static func district_fraction(site: Dictionary) -> Vector2:
 return Vector2(0.5, 0.5) + site_position(site) * 0.49

static func facility_kind(facility: Dictionary) -> String:
 var kind: String = str(facility.get("type", ""))
 if kind == "construction_site":
  return str(facility.get("construction_building_id", ""))
 if kind == "station" and str(facility.get("location", "")) == (
     str(facility.get("body", "")) + "-colony"):
  return "administrative_center"
 return kind

static func occupied(body: String, facilities: Array) -> Dictionary:
 var result: Dictionary = {}
 for raw in facilities:
  if not (raw is Dictionary) or str(raw.get("body", "")) != body:
   continue
  var key: String = str(raw.get("surface_site_id", ""))
  if not key.is_empty():
   result[key] = str(raw.get("id", ""))
 return result

static func free_sites(body: String, building_id: String,
        facilities: Array) -> Array:
 var claimed: Dictionary = occupied(body, facilities)
 var result: Array = []
 for entry in entries(body, building_id):
  if not claimed.has(str(entry.get("id", ""))):
   result.append(entry)
 return result

static func reservable(body: String, building_id: String,
        site_id: String, facilities: Array) -> Dictionary:
 if site_id.is_empty():
  return {}
 for entry in free_sites(body, building_id, facilities):
  if str(entry.get("id", "")) == site_id:
   return entry
 return {}

static func port_pads(body: String, facility: Dictionary) -> Dictionary:
 if facility_kind(facility) != "spaceport":
  return {}
 var entry: Dictionary = get_site(body, str(facility.get(
  "surface_site_id", "")))
 if entry.is_empty():
  return {}
 return {"site_id": str(entry.get("id", "")),
  "landing": entry.get("landing", {}),
  "loading": entry.get("loading", {})}

static func attach(facility: Dictionary, entry: Dictionary) -> void:
 facility["surface_site_id"] = str(entry.get("id", ""))
 if str(entry.get("kind", "ground")) == "ground":
  var at: Vector2 = site_position(entry)
  facility["surface_site"] = [at.x, at.y]

## Migrate legacy saves after validation, without adding, removing, or
## charging anything. Earlier coordinate-only facilities are assigned the
## nearest compatible still-free named site; pending sites retain their IDs.
## If the catalogue is exhausted, preserve the legacy coordinate unchanged.
static func reconcile(facilities: Array, queue: Array = []) -> void:
 for body in ["earth", "luna", "mars"]:
  var claimed: Dictionary = {}
  for raw in facilities:
   if not (raw is Dictionary) or str(raw.get("body", "")) != body:
    continue
   var existing: Dictionary = get_site(body, str(raw.get(
    "surface_site_id", "")))
   var kind: String = facility_kind(raw)
   var key: String = str(existing.get("id", ""))
   if not key.is_empty() and kind in existing.get("types", []) and (
       not claimed.has(key)):
    claimed[key] = str(raw.get("id", ""))
    attach(raw, existing)
   else:
    raw.erase("surface_site_id")
  for raw in facilities:
   if not (raw is Dictionary) or str(raw.get("body", "")) != body or (
       raw.has("surface_site_id")):
    continue
   var kind: String = facility_kind(raw)
   var possible: Array = entries(body, kind)
   if possible.is_empty():
    continue
   var prior: Vector2 = Vector2.ZERO
   var old: Variant = raw.get("surface_site", [])
   if old is Array and old.size() == 2:
    prior = Vector2(float(old[0]), float(old[1]))
   var chosen: Dictionary = {}
   var best: float = INF
   for site in possible:
    var id: String = str(site.get("id", ""))
    if claimed.has(id):
     continue
    var delta: float = site_position(site).distance_squared_to(prior)
    if delta < best:
     chosen = site
     best = delta
   if not chosen.is_empty():
    attach(raw, chosen)
    claimed[str(chosen["id"])] = str(raw.get("id", ""))
 for site in queue:
  if not (site is Dictionary):
   continue
  for facility in facilities:
   if str(facility.get("id", "")) != str(site.get("id", "")):
    continue
   if facility.has("surface_site_id"):
    site["surface_site_id"] = facility["surface_site_id"]
   break
