extends RefCounted
## Rust strategy/colony.rs: source-backed expedition eligibility, read-only.
## A proposal is NOT a colony, construction site, contract or teleport.
const LEGACY_SETTLERS := 10
const DIRECTOR_SETTLERS := 50
const MATERIAL_REQUIRED := 600
const SHIPMENT_SIZE := 200
const CONSTRUCTION_PAYMENT := 10000
const STARTUP_CAPITAL := 20000
const LABOR_REQUIRED := 150
const DOCK_TYPE := "construction_dock"

func can_rendezvous(orbit_radius: float, orbit_period: int, speed_modifier: float, ship_base_velocity: float) -> bool:
 if orbit_period <= 0 or not is_finite(orbit_radius) or not is_finite(speed_modifier) or not is_finite(ship_base_velocity): return false
 if orbit_radius < 0.0 or speed_modifier <= 0.0 or ship_base_velocity <= 0.0: return false
 return TAU * orbit_radius / float(orbit_period) < ship_base_velocity * speed_modifier

func project_budget(passenger_payment_per_head: int, wage_per_shift: int, director_present: bool) -> int:
 if passenger_payment_per_head < 0 or wage_per_shift < 0: return -1
 var settlers := DIRECTOR_SETTLERS if director_present else LEGACY_SETTLERS
 return 3 * CONSTRUCTION_PAYMENT + STARTUP_CAPITAL + LABOR_REQUIRED * wage_per_shift + settlers * passenger_payment_per_head

func candidate(body: Dictionary, occupied_bodies: Dictionary, active_sites: Array, registry_location: Dictionary, resources: Dictionary) -> Dictionary:
 var body_id := str(body.get("body_id",""))
 if body_id.is_empty() or body.get("body_type","") != "planet": return {"available":false,"reason":"not_planet"}
 if occupied_bodies.has(body_id): return {"available":false,"reason":"occupied"}
 for site in active_sites:
  if site is Dictionary and site.get("body_id","") == body_id and not site.get("completed",false):
   return {"available":false,"reason":"existing_site"}
 var raw := float(resources.get("ore",0.0)) + float(resources.get("ice",0.0)) + float(resources.get("gas",0.0))
 if not is_finite(raw) or raw <= 0.0: return {"available":false,"reason":"no_extraction_resource"}
 if registry_location.get("loc_type","") != "colony" or registry_location.get("celestial_body_id",null) != body.get("db_id",null):
  return {"available":false,"reason":"missing_native_colony_location"}
 return {"available":true,"reason":"eligible_body","destination":body_id + "-colony"}

func funding_gate(treasury: int, reserve: int, budget: int, source_population: int, settlers: int, source_metals: float, quote: int) -> Dictionary:
 if treasury < 0 or reserve < 0 or budget < 0 or settlers <= 0: return {"allowed":false,"reason":"invalid_budget"}
 if treasury - reserve < budget: return {"allowed":false,"reason":"insufficient_colony_budget"}
 if source_population < settlers * 2: return {"allowed":false,"reason":"insufficient_settlers"}
 if not is_finite(source_metals) or source_metals < float(MATERIAL_REQUIRED): return {"allowed":false,"reason":"insufficient_affordable_metals"}
 if quote < 0 or quote >= CONSTRUCTION_PAYMENT: return {"allowed":false,"reason":"insufficient_affordable_metals"}
 return {"allowed":true,"reason":"ready"}

func carrier_gate(ships: Array, faction: String, source: String, settlers: int, quote: int, orbit: Dictionary, base_velocity: float) -> Dictionary:
 var passenger := false
 var carrier := false
 var engineer := false
 for ship in ships:
  if not ship is Dictionary or ship.get("faction_id","") != faction or not ship.get("reachable_source",false): continue
  if float(ship.get("fuel_fraction",0.0)) <= 0.0: continue
  if not can_rendezvous(float(orbit.get("radius",-1.0)),int(orbit.get("period",0)),float(ship.get("speed_modifier",0.0)),base_velocity): continue
  passenger = passenger or int(ship.get("passenger_capacity",0)) >= settlers
  carrier = carrier or (int(ship.get("cargo_capacity",0)) >= SHIPMENT_SIZE and int(ship.get("credits",0)) >= quote)
  engineer = engineer or bool(ship.get("native_construction_capable",false))
 return {"passenger":passenger,"carrier":carrier,"engineer":engineer,"allowed":passenger and carrier and engineer}
