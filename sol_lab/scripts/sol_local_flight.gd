extends RefCounted
## Earth-centred inertial kilometres and native calendar time. The two
## terminal gates are the near sides of the existing colony/port approach
## orbits. The Moon line rotates; both gates carry its tangential velocity.
const Calendar = preload("res://scripts/sol_calendar.gd")
const Profile = preload("res://scripts/sol_profile.gd")
const LEGACY_DAYS := 12.0
const ACCELERATION := {"freight": 92000.0, "colonizer": 75000.0} # km / game day²

static func geometry(world: Dictionary) -> Dictionary:
 var moon: Dictionary = {}
 for body in world.get("bodies", []):
  if body.get("id") == "luna":
   moon = body
   break
 var spec: Dictionary = Profile.FROZEN_SOL_SATELLITES.luna
 var native_radius: float = moon.get("satellite_orbit_radius_native",
  float(spec.distance_km) * Profile.SOL_UNITS_PER_AU / Profile.KM_PER_AU)
 var period: float = moon.get("satellite_orbit_period_native",
  float(spec.sidereal_days) * Profile.NATIVE_EARTH_YEAR / Profile.EARTH_YEAR_DAYS)
 var km_per_unit := Profile.KM_PER_AU / Profile.SOL_UNITS_PER_AU
 return {"distance": native_radius * km_per_unit, "angle": -deg_to_rad(float(moon.get("current_angle", 0))),
  "omega": -TAU / period, "earth": Profile.compact_station_orbit_radius("earth") * km_per_unit,
  "luna": (native_radius - Profile.compact_station_orbit_radius("luna")) * km_per_unit}

static func make(world: Dictionary, kind: String, source: String,
        departure: float, saved_arrival: float = -1.0, destination := "") -> Dictionary:
 var target := destination if not destination.is_empty() else ("luna" if source == "earth" else "earth")
 var orbit := solar_geometry(world) if "mars" in [source, target] else geometry(world)
 var arrival := saved_arrival
 if arrival < 0.0:
  var native_day := Calendar.days_to_native(1.0)
  var limit: float = ACCELERATION[kind] / (native_day * native_day)
  # A cubic's acceleration is affine in time, so its maximum magnitude
  # is at one of the two ends. Solve against the future moving gate.
  var low := 0.0
  var high := sqrt(6.0 * gate(orbit, source, departure).distance_to(gate(orbit, target, departure)) / limit)
  while _peak_acceleration(_curve(orbit, source, target, departure, high), high) > limit:
   high *= 1.5
  for i in range(24):
   var duration := (low + high) * 0.5
   var curve := _curve(orbit, source, target, departure, duration)
   if _peak_acceleration(curve, duration) > limit:
    low = duration
   else:
    high = duration
  arrival = departure + high
 var path := _curve(orbit, source, target, departure, arrival - departure)
 path.orbit = orbit
 path.source = source
 path.destination = target
 path.departure = departure
 path.arrival = arrival
 # Only legacy deadlines require special handling: the older 12-day
 # flight can sweep over half the orbit with edited periods. A radial
 # transfer in the rotating frame keeps such saved runs outside the bodies.
 path.legacy = not orbit.has("solar") and is_equal_approx(arrival - departure, Calendar.days_to_native(LEGACY_DAYS))
 return path

static func _peak_acceleration(curve: Dictionary, duration: float) -> float:
 return maxf((2.0 * curve.b).length(), (6.0 * curve.a + 2.0 * curve.b).length()) / (
  duration * duration)

static func _curve(orbit: Dictionary, source: String, target: String,
        departure: float, duration: float) -> Dictionary:
 var p: Vector2 = gate(orbit, source, departure)
 var q: Vector2 = gate(orbit, target, departure + duration)
 var v: Vector2 = tangent(p, _omega(orbit, source)) * duration
 var w: Vector2 = tangent(q, _omega(orbit, target)) * duration
 return {"p": p, "a": 2.0 * (p - q) + v + w, "b": 3.0 * (q - p) - 2.0 * v - w, "c": v}

static func axis(orbit: Dictionary, time: float) -> Vector2:
 return Vector2.RIGHT.rotated(float(orbit.angle) + float(orbit.omega) * time)

static func solar_geometry(world: Dictionary) -> Dictionary:
 var orbits: Dictionary = {}
 for body in world.get("bodies", []):
  if body.get("id") in ["earth", "mars"]:
   orbits[body.id] = {
    "radius": float(body.orbit_radius) * Profile.KM_PER_AU / Profile.SOL_UNITS_PER_AU,
    "angle": -deg_to_rad(float(body.get("current_angle", 0.0))),
    "omega": -TAU / float(body.orbit_period)}
 return {"solar": orbits}

static func _omega(orbit: Dictionary, body: String) -> float:
 return orbit.solar[body].omega if orbit.has("solar") else orbit.omega

static func gate(orbit: Dictionary, body: String, time: float) -> Vector2:
 if orbit.has("solar"):
  var track: Dictionary = orbit.solar[body]
  return Vector2.RIGHT.rotated(track.angle + track.omega * time) * float(track.radius)
 return axis(orbit, time) * float(orbit[body])

static func tangent(point: Vector2, omega: float) -> Vector2:
 return Vector2(-point.y, point.x) * omega

static func progress(path: Dictionary, time: float) -> float:
 return clampf(inverse_lerp(path.departure, path.arrival, time), 0.0, 1.0)

static func position(path: Dictionary, time: float) -> Vector2:
 var u := progress(path, time)
 if u <= 0.0:
  return path.p
 if u >= 1.0:
  return gate(path.orbit, path.destination, path.arrival)
 if path.legacy:
  return axis(path.orbit, time) * lerpf(path.orbit[path.source],
   path.orbit[path.destination], u * u * (3.0 - 2.0 * u))
 return ((path.a * u + path.b) * u + path.c) * u + path.p

static func velocity(path: Dictionary, time: float) -> Vector2:
 var u := progress(path, time)
 var duration: float = path.arrival - path.departure
 if path.legacy:
  var at := lerpf(path.departure, path.arrival, u)
  var radial: float = (path.orbit[path.destination] - path.orbit[path.source]) * 6.0 * u * (1.0 - u)
  return tangent(position(path, at), path.orbit.omega) + axis(path.orbit, at) * radial / duration
 if u >= 1.0:
  return tangent(gate(path.orbit, path.destination, path.arrival), _omega(path.orbit, path.destination))
 return ((3.0 * path.a * u + 2.0 * path.b) * u + path.c) / duration

static func valid_times(ship: Dictionary, now: float) -> bool:
 var start: Variant = ship.get("departure")
 var end: Variant = ship.get("arrival")
 return (start is float or start is int) and (end is float or end is int) and (
  is_finite(end) and start >= 0.0 and start <= now and end > now)
