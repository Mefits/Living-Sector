extends Node

## Central data store for all world state received from the simulator.
## Other nodes connect to signals to react to state changes.

# Signals
signal world_loaded
signal tick_updated(tick: int)
signal positions_updated(positions_array: Array)
signal toast_requested(message: String, color: Color)
signal ship_removed(id: String)
signal ship_added(id: String)
signal facility_removed(id: String)
signal facility_added(id: String)
# Phase 19c: construction site lifecycle. `updated` fires on progress
# refresh; `removed` when the site materialises into a facility (or
# is otherwise despawned by the sim).
signal construction_site_updated(id: String)
signal construction_site_removed(id: String)
# Emitted after a facility_states WS broadcast is merged. Facility nodes
# that render dock glow / reserves listen for this to redraw. Fires ~every
# 2 s (tick % 16) at default pace.
signal facility_states_updated
# Emitted after population_states merge. Pop browser listens.
signal populations_updated
# Emitted after faction_states merge. Faction ledger listens.
signal factions_updated
# Emitted after contract_states merge. Contract board listens.
signal contracts_updated
# Fired once per incoming event (ship_docked, contract_delivered etc.)
# so toasts + tickers can react without polling.
signal event_received(event: Dictionary, tick: int)

# World data keyed by id
var ships: Dictionary = {}
var facilities: Dictionary = {}
# Phase 19c: in-flight construction sites keyed by `site-*` id.
# Populated from /api/construction_sites on boot + refreshed every
# ~2s alongside facility polls. Cleared when a site finishes
# (materialises into a real facility).
var construction_sites: Dictionary = {}
var markets: Dictionary = {}
var populations: Dictionary = {}
var systems: Dictionary = {}
var metrics: Dictionary = {}
# factions keyed by short faction_id slug (e.g. "terran-authority")
var factions: Dictionary = {}
# Contract snapshot keyed by contract id. Refreshed every ~4s from the
# contract_states broadcast. Same payload shape as /api/contracts.
var contracts: Dictionary = {}
# Rolling event ring buffer. Each entry = {tick, event: Dictionary}.
# Capped at EVENT_BUFFER_SIZE most-recent events for the events ticker +
# per-agent inspect trail to read without allocating.
var event_log: Array = []
const EVENT_BUFFER_SIZE := 400
# Rolling perf sample from /api/health (p50 / p99 compute_us). Updated by
# network_manager on /api/report refresh.
var tick_compute_p50_us: int = 0
var tick_compute_p99_us: int = 0
# Spatial-LOD tier distribution (agent counts per divisor). Populated
# from the same perf block. Perf HUD reads this to show "215 @ d=1,
# 8 @ d=50" at a glance.
var lod_d1: int = 0
var lod_d2: int = 0
var lod_d5: int = 0
var lod_d10: int = 0
var lod_d20: int = 0
var lod_d50: int = 0

# Simulation state
var tick: int = 0
var running: bool = false
var tick_interval_ms: int = 125
var tick_scale: float = 0.03125  # world_speed / ticks_per_second
# Game-time multiplier (gameplay pace). Independent of tick_interval_ms
# (which is resolution/smoothness). HUD speed buttons route here via
# POST /api/sim/speed {world_speed: N}. Server echoes the current value
# back on server_hello + sim_control_ack.
var world_speed: float = 0.25
# Rolling EMA of wall-clock gap between simulation:positions broadcasts.
# NetworkManager maintains this; interpolation reads it instead of the
# server-reported tick_interval_ms so ships visually scale with sim speed
# even if the server's reported cadence drifts from reality.
var observed_interval_ms: int = 0
# Ticks elapsed per positions broadcast. Diagnostic only.
var ticks_per_broadcast: int = 1

# Coordinate mapping
const SCALE_FACTOR := 10.0

# Zoom level tracking — updated by camera, read by anything
# Tiers (like Google Maps): street < neighborhood < city < region < world
enum ZoomTier { CLOSE, LOCAL, SYSTEM, REGION, GALAXY }
var zoom_raw: float = 80.0        # Raw camera zoom value
var zoom_tier: ZoomTier = ZoomTier.SYSTEM
signal zoom_changed(tier: ZoomTier, raw: float)

# Tier thresholds (camera zoom_level values)
const ZOOM_THRESHOLDS := {
	15.0: ZoomTier.CLOSE,       # Individual ships visible
	40.0: ZoomTier.LOCAL,       # Planet neighborhood
	100.0: ZoomTier.SYSTEM,     # Full star system
	200.0: ZoomTier.REGION,     # Multiple systems
}
# Above 200 = GALAXY


func update_zoom(raw: float) -> void:
	zoom_raw = raw
	var new_tier: ZoomTier = ZoomTier.GALAXY
	for threshold in ZOOM_THRESHOLDS:
		if raw <= threshold:
			new_tier = ZOOM_THRESHOLDS[threshold]
			break
	if new_tier != zoom_tier:
		zoom_tier = new_tier
	zoom_changed.emit(zoom_tier, raw)

# Fallback system offsets — overridden by API data when available
const DEFAULT_SYSTEM_OFFSETS := {
	"system-sol": Vector2(0.0, 0.0),
	"system-alpha-centauri": Vector2(20.0, 5.0),
	"system-tau-ceti": Vector2(40.0, -10.0),
}

# Populated from API (offset_x, offset_y per system)
var system_offsets: Dictionary = {}

var selected_entity_id: String = ""


func show_toast(
	message: String, color: Color = ThemePalette.TEXT
) -> void:
	toast_requested.emit(message, color)
var _world_loaded := false


func server_to_world(x: float, y: float) -> Vector3:
	return Vector3(x * SCALE_FACTOR, 0.0, y * SCALE_FACTOR)


const GOAL_LABELS := {
	"trade_run": "Trade Run",
	"fulfill_delivery": "Delivery",
	"fulfill_contract": "Contract",
	"fulfill_passenger_transport": "Passenger Transport",
	"refuel": "Refuel",
	"rest_crew": "Rest Crew",
	"explore": "Explore",
	"sell_cargo": "Liquidate Cargo",
	"station_job": "Station Job",
	"do_crew_mission": "Crew Mission",
	"seek_retrofit": "Seek Retrofit",
	"fulfill_construction": "Construction",
	"idle": "Idle",
}


func faction_name(slug: Variant) -> String:
	## Prettify a faction_id slug to its display name (falls back to a
	## humanized slug for unknown ids).
	if slug == null:
		return "-"
	var key: String = str(slug)
	if key == "" or key == "null":
		return "-"
	var fac: Dictionary = factions.get(key, {})
	var n: String = str(fac.get("name", ""))
	if n != "":
		return n
	return key.replace("-", " ").replace("_", " ").capitalize()


func goal_label(goal: Variant) -> String:
	if goal == null:
		return "-"
	var key: String = str(goal)
	if key == "" or key == "null":
		return "-"
	if GOAL_LABELS.has(key):
		return GOAL_LABELS[key]
	# Fall back to humanizing the raw key for anything new the server adds
	return key.replace("_", " ").capitalize()


func get_system_offset(system_id: String) -> Vector2:
	if system_offsets.has(system_id):
		return system_offsets[system_id]
	return DEFAULT_SYSTEM_OFFSETS.get(system_id, Vector2.ZERO)


func get_tick_interval_seconds() -> float:
	return tick_interval_ms / 1000.0


func get_effective_interval_seconds() -> float:
	## Preferred interval for anything interpolating between broadcasts.
	## Uses the observed wall-clock gap between positions events — robust
	## to the server misreporting `interval_ms` when sim speed changes.
	## Clamped low (~8 ms) to avoid divide-by-zero or runaway lerp speed
	## during a packet-drain burst on alt-tab resume.
	var result: float
	if observed_interval_ms > 0:
		result = observed_interval_ms / 1000.0
	else:
		result = tick_interval_ms / 1000.0
	return maxf(result, 0.008)


func load_world_snapshot(data: Dictionary) -> void:
	tick = data.get("tick", 0)
	running = data.get("running", false)
	metrics = data.get("metrics", {})

	# Read simulation config
	var config: Dictionary = data.get("config", {})
	if config.size() > 0:
		tick_interval_ms = int(config.get("tick_interval_ms", 125))
		tick_scale = float(config.get("tick_scale", 0.03125))
		world_speed = float(config.get("world_speed", world_speed))

	# Index systems by id and extract offsets
	systems.clear()
	system_offsets.clear()
	for system in data.get("systems", []):
		var sys_id: String = system["id"]
		systems[sys_id] = system
		var ox: float = float(system.get("offset_x", 0.0))
		var oy: float = float(system.get("offset_y", 0.0))
		system_offsets[sys_id] = Vector2(ox, oy)

	# Index ships by id
	ships.clear()
	for ship in data.get("ships", []):
		ships[ship["id"]] = ship

	# Index facilities by id
	facilities.clear()
	for facility in data.get("facilities", []):
		facilities[facility["id"]] = facility

	# Index markets by id
	markets.clear()
	for market in data.get("markets", []):
		markets[market["id"]] = market

	# Index populations by id
	populations.clear()
	for pop in data.get("populations", []):
		populations[pop["id"]] = pop

	# Index factions by short slug (faction_id). Server payload uses
	# long "id": "faction-<slug>" — key by the slug for easy lookup
	# from ships/facilities that only carry the slug form.
	factions.clear()
	for faction in data.get("factions", []):
		var slug: String = str(faction.get(
			"faction_id", faction.get("id", "")
		))
		if slug != "":
			factions[slug] = faction

	_world_loaded = true
	world_loaded.emit()


func refresh_world_data(data: Dictionary) -> void:
	## Periodic refresh — merges metadata fields without touching positions.
	var config: Dictionary = data.get("config", {})
	if config.size() > 0:
		tick_interval_ms = int(config.get("tick_interval_ms", tick_interval_ms))
		tick_scale = float(config.get("tick_scale", tick_scale))
		world_speed = float(config.get("world_speed", world_speed))
	# /api/health-style perf block lands here via /api/report metadata
	# when the server is new enough to expose it. Safe fall-throughs.
	var perf: Dictionary = data.get("perf", {})
	if perf.size() > 0:
		tick_compute_p50_us = int(perf.get("tick_compute_p50_us", tick_compute_p50_us))
		tick_compute_p99_us = int(perf.get("tick_compute_p99_us", tick_compute_p99_us))
		var lod: Dictionary = perf.get("lod", {})
		if lod.size() > 0:
			lod_d1 = int(lod.get("d1", 0))
			lod_d2 = int(lod.get("d2", 0))
			lod_d5 = int(lod.get("d5", 0))
			lod_d10 = int(lod.get("d10", 0))
			lod_d20 = int(lod.get("d20", 0))
			lod_d50 = int(lod.get("d50", 0))

	# Merge ship metadata (never touch position — WS handles that).
	# Track the set of ids the report included so we can drop anything
	# local-only afterward — critical for admin-destroyed agents where
	# the client had removed the entry, then a stale /api/report could
	# have resurrected it.
	var report_ship_ids: Dictionary = {}
	for ship in data.get("ships", []):
		var id: String = ship.get("id", "")
		if id == "":
			continue
		report_ship_ids[id] = true
		if ships.has(id):
			for key in ship:
				if key != "position":
					ships[id][key] = ship[key]
		else:
			ships[id] = ship
	# Prune: any ship we have locally that's NOT in the report is
	# genuinely gone server-side. Fire the removal path so 3D nodes
	# queue_free and the selection clears.
	var stale_ship_ids: Array = []
	for sid in ships:
		if not report_ship_ids.has(sid):
			stale_ship_ids.append(sid)
	for sid in stale_ship_ids:
		remove_ship_local(sid)

	# Merge facility metadata (same prune pattern as ships).
	var report_fac_ids: Dictionary = {}
	for facility in data.get("facilities", []):
		var id: String = facility.get("id", "")
		if id == "":
			continue
		report_fac_ids[id] = true
		if facilities.has(id):
			for key in facility:
				if key != "position":
					facilities[id][key] = facility[key]
		else:
			facilities[id] = facility
	var stale_fac_ids: Array = []
	for fid in facilities:
		if not report_fac_ids.has(fid):
			stale_fac_ids.append(fid)
	for fid in stale_fac_ids:
		remove_facility_local(fid)

	# Phase 19c: construction sites. Full snapshot + prune so sites
	# that finished (materialised into facilities) fire the
	# `construction_site_removed` signal to tear down their scaffold.
	var sites_array: Array = data.get("construction_sites", [])
	if sites_array is Array:
		update_construction_sites(sites_array)

	for market in data.get("markets", []):
		markets[market["id"]] = market
	for pop in data.get("populations", []):
		populations[pop["id"]] = pop

	# Refresh factions (treasury, active subsidies, shortage_cache all drift)
	for faction in data.get("factions", []):
		var slug: String = str(faction.get(
			"faction_id", faction.get("id", "")
		))
		if slug != "":
			factions[slug] = faction


func update_tick(new_tick: int) -> void:
	tick = new_tick
	tick_updated.emit(new_tick)


func update_positions(positions_array: Array) -> void:
	## Handles both ship and facility positions from the positions channel.
	## Distinguish by ID prefix: ship-* vs facility-*
	for entry in positions_array:
		var id: String = entry.get("id", "")
		var x = entry.get("x", 0.0)
		var y = entry.get("y", 0.0)
		if id.begins_with("ship-"):
			if ships.has(id):
				ships[id]["position"] = {"x": x, "y": y}
		elif id.begins_with("facility-"):
			if facilities.has(id):
				facilities[id]["position"] = {"x": x, "y": y}
	positions_updated.emit(positions_array)


func update_ship_states(states_array: Array) -> void:
	## FULL ship snapshot from the ship_states WS event (~every 1s).
	## Per-entry fields are merged into the existing dict (missing
	## fields on an entry preserve prior values — the server sometimes
	## omits fields that didn't change), but the ARRAY itself is full:
	## any ship we have locally that's NOT in the broadcast has been
	## removed server-side, so prune it. `position` is always skipped
	## (WS positions channel owns that). Server field "goal" is
	## normalized to our internal "current_goal" so UI code stays
	## consistent.
	var seen: Dictionary = {}
	for entry in states_array:
		if not (entry is Dictionary):
			continue
		var id: String = entry.get("id", "")
		if id == "":
			continue
		seen[id] = true
		if not ships.has(id):
			# New ship (admin spawn from another client, reconnect) —
			# copy wholesale so future partial updates land somewhere.
			ships[id] = entry.duplicate()
			ship_added.emit(id)
			continue
		for key in entry:
			if key == "id" or key == "position":
				continue
			# Normalize server field names to our internal names. The
			# /api/report snapshot uses "current_goal" and "current_bt"
			# while the ship_states WS payload uses "goal" and "bt".
			var target_key: String = key
			if key == "goal":
				target_key = "current_goal"
			elif key == "bt":
				target_key = "current_bt"
			ships[id][target_key] = entry[key]
	# Prune any ship that's local-only — server has removed it.
	var stale: Array = []
	for sid in ships:
		if not seen.has(sid):
			stale.append(sid)
	for sid in stale:
		remove_ship_local(sid)


func update_markets(markets_array: Array) -> void:
	## Full market snapshot from the simulation:markets WS channel.
	## Server sends every ~2s; we overwrite by id. Payload includes
	## prices, supply, demand, shortage_ticks per market.
	for entry in markets_array:
		if not (entry is Dictionary):
			continue
		var id: String = str(entry.get("id", ""))
		if id == "":
			continue
		markets[id] = entry


func update_facilities(facilities_array: Array) -> void:
	## Full facility snapshot from the facility_states WS channel.
	## Every field except `position` is overwritten — positions come from
	## the per-tick positions broadcast and we never want a 2-second-stale
	## position clobbering the live one.
	##
	## This is a FULL snapshot — any facility we have locally that's not
	## in the broadcast was destroyed server-side, so prune it. Without
	## this, admin-destroyed facilities linger in the UI until a Godot
	## restart even when the server has correctly dropped them.
	var seen: Dictionary = {}
	for entry in facilities_array:
		if not (entry is Dictionary):
			continue
		var id: String = str(entry.get("id", ""))
		if id == "":
			continue
		seen[id] = true
		if facilities.has(id):
			for key in entry:
				if key == "position":
					continue
				facilities[id][key] = entry[key]
		else:
			# New-to-us facility (admin spawn, reconnect). Copy wholesale.
			facilities[id] = entry
	var stale: Array = []
	for fid in facilities:
		if not seen.has(fid):
			stale.append(fid)
	for fid in stale:
		remove_facility_local(fid)
	facility_states_updated.emit()


func update_construction_sites(sites_array: Array) -> void:
	## Phase 19c: full construction-site snapshot poll. Sites that
	## vanish from the array have materialised into real facilities
	## (or were admin-despawned); we emit `construction_site_removed`
	## so universe.gd can queue_free the scaffold visual.
	var seen: Dictionary = {}
	for entry in sites_array:
		if not (entry is Dictionary):
			continue
		var id: String = str(entry.get("id", ""))
		if id == "":
			continue
		seen[id] = true
		construction_sites[id] = entry
		construction_site_updated.emit(id)
	# Prune + emit removed for anything no longer in the broadcast.
	var gone: Array = []
	for id in construction_sites.keys():
		if not seen.has(id):
			gone.append(id)
	for id in gone:
		construction_sites.erase(id)
		construction_site_removed.emit(id)


func update_populations_full(populations_array: Array) -> void:
	## Full population snapshot from the population_states WS channel.
	## Pop browser panel reacts via `populations_updated`.
	for entry in populations_array:
		if not (entry is Dictionary):
			continue
		var id: String = str(entry.get("id", ""))
		if id == "":
			continue
		populations[id] = entry
	populations_updated.emit()


func update_factions_full(factions_array: Array) -> void:
	## Full faction snapshot with treasury + active_subsidies. Merge into
	## the existing `factions` dict keyed by short slug.
	for entry in factions_array:
		if not (entry is Dictionary):
			continue
		var slug: String = str(entry.get(
			"faction_id", entry.get("id", "")
		))
		if slug == "":
			continue
		# Normalize keying: the report.endpoint uses "id", the broadcast
		# uses short slug — strip the "faction-" prefix if present.
		if slug.begins_with("faction-"):
			slug = slug.substr(8)
		factions[slug] = entry
	factions_updated.emit()


func update_contracts(contracts_array: Array) -> void:
	## Replace the contract snapshot wholesale. The server already drops
	## Paid/Expired entries from the broadcast, so we mirror by clearing
	## stale keys that weren't in this batch.
	var seen: Dictionary = {}
	for entry in contracts_array:
		if not (entry is Dictionary):
			continue
		var id: String = str(entry.get("id", ""))
		if id == "":
			continue
		contracts[id] = entry
		seen[id] = true
	for id in contracts.keys():
		if not seen.has(id):
			contracts.erase(id)
	contracts_updated.emit()


func append_events(tick: int, events_array: Array) -> void:
	## Push new events onto the ring buffer, capped at EVENT_BUFFER_SIZE.
	## Fires `event_received(event, tick)` per entry so toasts / tickers
	## update live without polling.
	for ev in events_array:
		if not (ev is Dictionary):
			continue
		event_log.append({"tick": tick, "event": ev})
		event_received.emit(ev, tick)
	if event_log.size() > EVENT_BUFFER_SIZE:
		event_log = event_log.slice(event_log.size() - EVENT_BUFFER_SIZE)


func events_for_agent(agent_id: String, limit: int = 50) -> Array:
	## Filter the event ring for events mentioning `agent_id` (by id or
	## ship-specific fields). Used by the inspect trail in details_panel.
	var out: Array = []
	var i := event_log.size() - 1
	while i >= 0 and out.size() < limit:
		var entry: Dictionary = event_log[i]
		var ev: Dictionary = entry.get("event", {})
		var matches := false
		if str(ev.get("id", "")) == agent_id:
			matches = true
		elif str(ev.get("contract_id", "")) == agent_id:
			matches = true
		elif str(ev.get("location", "")) == agent_id:
			matches = true
		if matches:
			out.append(entry)
		i -= 1
	return out


func add_ship_local(ship_data: Dictionary) -> void:
	## Eagerly add a newly-created ship to client state. Called after
	## admin_create_ship returns 201. The server response is partial —
	## no position / cargo / fuel — so we seed the ship at its starting
	## facility's position (if known) and let subsequent positions /
	## ship_states broadcasts fill in the rest.
	var id: String = str(ship_data.get("id", ""))
	if id == "":
		return
	if not ship_data.has("position"):
		var loc: String = str(ship_data.get("location", ""))
		if loc != "":
			for fac in facilities.values():
				if str(fac.get("location", "")) == loc:
					var fp = fac.get("position", {})
					if fp is Dictionary:
						ship_data["position"] = fp
					break
	ships[id] = ship_data
	ship_added.emit(id)


func add_facility_local(fac_data: Dictionary) -> void:
	## Same for facilities. Normalize id (server sometimes returns the
	## slug as facility_id, sometimes the full facility-<slug>). Seed
	## the initial position from the parent body so the 3D node doesn't
	## pop in at origin while we wait for the first positions broadcast.
	var raw_id: String = str(
		fac_data.get("id", fac_data.get("facility_id", ""))
	)
	if raw_id == "":
		return
	var id: String = raw_id
	if not id.begins_with("facility-"):
		id = "facility-" + id
	var entry: Dictionary = fac_data.duplicate()
	entry["id"] = id
	if not entry.has("position"):
		var body_id: String = str(entry.get("body_id", ""))
		if body_id != "":
			for sys_data in systems.values():
				for body in sys_data.get("bodies", []):
					if str(body.get("id", "")) == body_id:
						var bx = body.get("x")
						var by = body.get("y")
						if bx != null and by != null:
							entry["position"] = {"x": float(bx), "y": float(by)}
						break
	facilities[id] = entry
	facility_added.emit(id)


func remove_ship_local(id: String) -> void:
	## Eagerly clean up a ship from client state. Used after admin
	## destroy returns 204 (we don't want to wait for, or rely on,
	## the server's ship_decommissioned event round-trip). Idempotent —
	## safe to call even if the server's broadcast also fires.
	if ships.has(id):
		ships.erase(id)
	if selected_entity_id == id:
		selected_entity_id = ""
	ship_removed.emit(id)


func remove_facility_local(id: String) -> void:
	## Same pattern for facilities. There's no ship_removed-equivalent
	## cascade today (no server event subscribed), so this is the
	## cleanup path after admin destroy.
	if facilities.has(id):
		facilities.erase(id)
	if selected_entity_id == id:
		selected_entity_id = ""
	facility_removed.emit(id)


func handle_ship_event(event: String, payload: Dictionary) -> void:
	## Episodic per-ship events from simulation:ship_events.
	## Most fields are redundant with ship_states deltas; we mainly care
	## about decommission (cleanup) and dramatic moments (toasts).
	var id: String = str(payload.get("id", ""))
	if id == "":
		return

	match event:
		"ship_decommissioned":
			var label: String = _ship_label(id, payload)
			remove_ship_local(id)
			_toast_if_selected(
				id,
				"%s decommissioned" % label,
				ThemePalette.DANGER
			)
		"ship_departed":
			_toast_if_selected(
				id,
				"%s departed for %s" % [
					_ship_label(id, payload),
					str(payload.get("to", "?"))
				],
				ThemePalette.PRIMARY
			)
		"ship_arrived":
			_toast_if_selected(
				id,
				"%s arrived at %s" % [
					_ship_label(id, payload),
					str(payload.get("to", payload.get("location", "?")))
				],
				ThemePalette.SUCCESS
			)
		"goal_changed":
			_toast_if_selected(
				id,
				"%s: %s" % [
					_ship_label(id, payload),
					str(payload.get("goal", "?")).replace("_", " ")
				],
				ThemePalette.WARN
			)
		# "docked" / "undocked" — redundant with ship_states, skip toast spam
		_:
			pass


func _ship_label(id: String, payload: Dictionary) -> String:
	var ship: Dictionary = ships.get(id, {})
	return str(ship.get("name", payload.get("name", id)))


func _toast_if_selected(id: String, msg: String, color: Color) -> void:
	if selected_entity_id == id:
		toast_requested.emit(msg, color)


func handle_subsidy_posted(payload: Dictionary) -> void:
	## Called when simulation:faction:<id> fires a subsidy_posted event.
	## These are loud faction-scale moments, so always toast (not
	## gated on current selection). Bursts — e.g. 20 subsidies posted
	## on the same tick across many factions — get coalesced into a
	## single summary toast so we don't flood the scene tree with
	## Label + Tween churn on one frame.
	_pending_subsidies.append(payload)
	if not _subsidy_flush_scheduled:
		_subsidy_flush_scheduled = true
		get_tree().create_timer(
			SUBSIDY_COALESCE_SEC
		).timeout.connect(_flush_subsidy_toasts)


const SUBSIDY_COALESCE_SEC := 0.25
var _pending_subsidies: Array = []
var _subsidy_flush_scheduled: bool = false


func _flush_subsidy_toasts() -> void:
	_subsidy_flush_scheduled = false
	var pending: Array = _pending_subsidies
	_pending_subsidies = []
	if pending.size() == 0:
		return
	if pending.size() == 1:
		var p: Dictionary = pending[0]
		var fac_slug: String = str(p.get("faction_id", ""))
		var commodity: String = str(p.get("commodity", "?"))
		var dest: String = str(p.get("destination", "?"))
		var payment: int = int(p.get("payment", 0))
		toast_requested.emit(
			"%s: %d cr for %s → %s" % [
				faction_name(fac_slug), payment, commodity, dest
			],
			ThemePalette.WARN
		)
		return
	# Burst → single summary toast.
	var total_payment: int = 0
	var factions_set: Dictionary = {}
	for p in pending:
		total_payment += int(p.get("payment", 0))
		factions_set[str(p.get("faction_id", ""))] = true
	toast_requested.emit(
		"%d subsidies posted (%d factions, %d cr total)" % [
			pending.size(), factions_set.size(), total_payment
		],
		ThemePalette.WARN
	)
