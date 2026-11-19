extends RefCounted
## The route has one ship. Its cargo belongs to the ship until touchdown.
const Calendar = preload("res://scripts/sol_calendar.gd")
const LOAD := 10
const DAYS := 12
var location := "earth"
var cargo := 0
var arrival := 0.0

func depart(supply: Dictionary, now: float) -> bool:
 if location != "earth" or float(supply.get("metals", 0)) < LOAD:
  return false
 supply.metals -= LOAD
 cargo = LOAD
 arrival = now + Calendar.days_to_native(DAYS)
 location = "transit"
 return true

func unload(supply: Dictionary) -> void:
 supply["metals"] = float(supply.get("metals", 0)) + cargo
 location = "luna"
 cargo = 0
 arrival = 0.0

func progress(now: float) -> float:
 if location == "earth":
  return 0.0
 if location == "luna":
  return 1.0
 return clampf(1.0 - (arrival - now) / Calendar.days_to_native(DAYS), 0.0, 1.0)

func snapshot() -> Dictionary:
 return {"location": location, "cargo": cargo, "arrival": arrival}

func restore(data: Variant, now: float, lunar_port: bool) -> bool:
 if not data is Dictionary:
  return false
 var place: Variant = data.get("location")
 var end: Variant = data.get("arrival")
 if not (end is int or end is float) or not is_finite(float(end)):
  return false
 if place == "transit":
  if not lunar_port or data.get("cargo") != LOAD or end <= now or end > now + Calendar.days_to_native(DAYS) + 0.000001:
   return false
 elif place in ["earth", "luna"]:
  if data.get("cargo") != 0 or end != 0 or (place == "luna" and not lunar_port):
   return false
 else:
  return false
 location = place
 cargo = int(data.cargo)
 arrival = float(end)
 return true
