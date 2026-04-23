extends Node

## Network layer for the Rust simulator (`spaceproject/simulator-rust/`).
##
## Protocol: plain JSON over WebSocket (no Phoenix channel envelope).
## See `crates/sim_server/src/ws/protocol.rs` for the message types.
##
## Server → client (pushed):
##   {"type": "server_hello",  "tick", "running", "agent_count", "interval_ms"}
##   {"type": "positions",     "tick", "interval_ms", "entities": [{id, x, y, type}]}
##   {"type": "ship_states",   "tick", "ships": [...]}
##   {"type": "market_states", "tick", "markets": [...]}
##   {"type": "agent_state",   "id", "data"}
##   {"type": "sim_control_ack", "action", "tick", "running"}
##
## Client → server:
##   {"type": "hello", "client_id": "..."}
##   {"type": "get_agent", "id": "ship-artemis-7"}
##   {"type": "get_snapshot", "agent_type": "ships"}
##   {"type": "move_observer", "id", "x", "y", "radius"}
##   {"type": "sim_control", "action": "pause" | "resume" | "set_speed" | "get_tick", ...}
##
## Previous version (Phoenix Channels v2 against the Elixir simulator) is
## preserved as `network_manager_phoenix.gd.bak` for reference.

signal connected
signal disconnected

const DEFAULT_BASE_URL := "http://localhost:8080"
const DEFAULT_WS_URL := "ws://localhost:8080/ws"
const REFRESH_INTERVAL := 30.0
const RECONNECT_DELAY := 2.0

# Debug flags — DEBUG_WS_TRAFFIC is noisy (~8 messages/sec from positions
# broadcast alone); enable only when diagnosing a specific message.
const DEBUG_WS := true
const DEBUG_WS_TRAFFIC := false

# Inbound can peak at ~200 KB (ship_states with 223 ships every 8 ticks).
# 4 MB gives headroom for larger fleets or burst reconnects.
const WS_INBOUND_BUFFER := 4 * 1024 * 1024
const WS_OUTBOUND_BUFFER := 1 * 1024 * 1024
const WS_MAX_QUEUED_PACKETS := 4096
# Cap per-frame packet drain so a backlog after alt-tab is a brief
# catch-up, not a multi-second freeze. Normal peak ~15/frame at 60 fps.
const MAX_PACKETS_PER_FRAME := 150

var _http: HTTPRequest
var _refresh_http: HTTPRequest
var _pending_callback: Callable
var _refresh_timer: float = 0.0

# WebSocket state
var _ws: WebSocketPeer
var _ws_state: int = WebSocketPeer.STATE_CLOSED
var _reconnect_timer: float = -1.0

# Cadence tracking for positions broadcasts (EMA smooth).
var _last_positions_ms: int = -1
var _last_positions_tick: int = -1


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.request_completed.connect(_on_http_completed)
	add_child(_http)

	_refresh_http = HTTPRequest.new()
	_refresh_http.timeout = 30.0
	_refresh_http.request_completed.connect(_on_refresh_completed)
	add_child(_refresh_http)


# -------------------- URL resolution --------------------

func _base_url() -> String:
	if ServerManager != null:
		return "http://%s:%d" % [ServerManager.host(), ServerManager.port()]
	return DEFAULT_BASE_URL


func _ws_url() -> String:
	if ServerManager != null:
		return "ws://%s:%d/ws" % [ServerManager.host(), ServerManager.port()]
	return DEFAULT_WS_URL


# -------------------- HTTP --------------------

func fetch_report(callback: Callable) -> void:
	_pending_callback = callback
	var url := _base_url() + "/api/report"
	print("[Network] fetch_report → %s" % url)
	var err := _http.request(url)
	if err != OK:
		push_error("[Network] fetch_report request() rejected: %d" % err)


func post_sim_control(action: String, params: Dictionary = {}) -> void:
	var url: String
	var body := ""
	var headers := PackedStringArray(["Content-Type: application/json"])

	match action:
		"pause":
			url = _base_url() + "/api/sim/pause"
		"resume":
			url = _base_url() + "/api/sim/resume"
		"set_world_speed", "set_ticks_per_second":
			# Unified POST /api/sim/speed endpoint — takes any subset of
			# {world_speed, ticks_per_second, interval_ms}.
			url = _base_url() + "/api/sim/speed"
			body = JSON.stringify(params)
		"step":
			# Advance N forced ticks while paused. Body: {ticks: u32}.
			url = _base_url() + "/api/sim/step"
			body = JSON.stringify(params)
		_:
			push_warning("Unknown sim control action: " + action)
			return

	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	req.request(url, headers, HTTPClient.METHOD_POST, body)


func _on_http_completed(
	result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error(
			"[Network] fetch_report failed: result=%d response_code=%d body_bytes=%d"
			% [result, response_code, body.size()]
		)
		if body.size() > 0 and body.size() < 4096:
			push_error("[Network] body: %s" % body.get_string_from_utf8())
		return
	print("[Network] fetch_report got %d bytes" % body.size())
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		push_error("[Network] fetch_report: JSON parse failed")
		return
	if _pending_callback.is_valid():
		_pending_callback.call(json)
		_pending_callback = Callable()


func _refresh_report() -> void:
	_refresh_http.request(_base_url() + "/api/report")


func _on_refresh_completed(
	result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning(
			"[Network] 30s refresh failed: result=%d response_code=%d"
			% [result, response_code]
		)
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		push_warning("[Network] 30s refresh: JSON parse failed")
		return
	if GameState.has_method("refresh_world_data"):
		GameState.refresh_world_data(json)


func disconnect_ws() -> void:
	if _ws != null:
		_ws.close(1000, "client disconnect")
	_reconnect_timer = -1.0


# -------------------- Admin (not yet wired in Rust server) --------------------
#
# The Rust simulator's HTTP API currently only exposes read + sim-control
# endpoints. Admin / god-mode endpoints (ship spawn, facility spawn,
# save-as, market supply delta) will be added in a later phase. For now
# these callbacks fire with response_code=404.

func admin_create_ship(data: Dictionary, cb: Callable) -> void:
	_admin_request(HTTPClient.METHOD_POST, "/api/admin/ships", data, cb)


func admin_destroy_ship(ship_id: String, cb: Callable) -> void:
	_admin_request(HTTPClient.METHOD_DELETE, "/api/admin/ships/" + ship_id, null, cb)


func admin_create_facility(data: Dictionary, cb: Callable) -> void:
	_admin_request(HTTPClient.METHOD_POST, "/api/admin/facilities", data, cb)


func admin_destroy_facility(facility_id: String, cb: Callable) -> void:
	_admin_request(
		HTTPClient.METHOD_DELETE,
		"/api/admin/facilities/" + facility_id,
		null, cb
	)


func admin_save(cb: Callable) -> void:
	_admin_request(HTTPClient.METHOD_POST, "/api/admin/save", null, cb)


func admin_save_as(save_name: String, cb: Callable) -> void:
	_admin_request(
		HTTPClient.METHOD_POST, "/api/admin/save-as",
		{"name": save_name}, cb
	)


func admin_market_supply_delta(
	facility_location: String, commodity: String, delta: int, cb: Callable
) -> void:
	var path := "/api/admin/markets/" + facility_location + "/supply"
	var body := {"commodity": commodity, "delta": delta}
	_admin_request(HTTPClient.METHOD_POST, path, body, cb)


func _admin_request(
	method: int, path: String, body: Variant, cb: Callable
) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(_result: int, code: int,
			_headers: PackedStringArray, resp_body: PackedByteArray) -> void:
			req.queue_free()
			if cb.is_valid():
				cb.call(code, resp_body.get_string_from_utf8())
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body_text := "" if body == null else JSON.stringify(body)
	req.request(_base_url() + path, headers, method, body_text)


# -------------------- WebSocket --------------------

func connect_websocket() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = WS_INBOUND_BUFFER
	_ws.outbound_buffer_size = WS_OUTBOUND_BUFFER
	_ws.max_queued_packets = WS_MAX_QUEUED_PACKETS
	var url := _ws_url()
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("[Network] WebSocket connect_to_url failed: %d" % err)
		_reconnect_timer = RECONNECT_DELAY
		return
	if DEBUG_WS:
		print("[Network] WebSocket connecting to %s..." % url)


func send_move_observer(
	id: String, x: float, y: float, radius: float = 20.0
) -> void:
	if _ws_state != WebSocketPeer.STATE_OPEN:
		return
	var msg := {
		"type": "move_observer",
		"id": id,
		"x": x,
		"y": y,
		"radius": radius,
	}
	_ws.send_text(JSON.stringify(msg))


func send_get_agent(id: String) -> void:
	if _ws_state != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify({"type": "get_agent", "id": id}))


func send_sim_control(action: String, extra: Dictionary = {}) -> void:
	if _ws_state != WebSocketPeer.STATE_OPEN:
		# Fallback to HTTP
		post_sim_control(action, extra)
		return
	var msg := {"type": "sim_control", "action": action}
	for k in extra.keys():
		msg[k] = extra[k]
	_ws.send_text(JSON.stringify(msg))


func set_world_speed(world_speed: float) -> void:
	## Tune game-time pace. 1.0 = real-time. 0.25 = 4× slower (default).
	## 4.0 = demo-fast. 0.0 is equivalent to pause but preserves the value.
	## Does NOT change tick resolution (client smoothness).
	send_sim_control("set_world_speed", {"world_speed": world_speed})


func set_ticks_per_second(tps: int) -> void:
	## Tune client smoothness. 8 = default, 16 = smoother, 2 = chunky/cheap.
	## Does NOT change game-time pace (world_speed stays put).
	send_sim_control("set_ticks_per_second", {"tps": tps})


func _process(delta: float) -> void:
	# HTTP report refresh cadence
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_report()

	# Reconnect countdown
	if _reconnect_timer >= 0.0:
		_reconnect_timer -= delta
		if _reconnect_timer < 0.0:
			print("[Network] Reconnecting...")
			connect_websocket()
		return

	if _ws == null:
		return

	_ws.poll()
	var new_state := _ws.get_ready_state()

	if new_state != _ws_state:
		if DEBUG_WS:
			print(
				"[Network] WS state: %s -> %s" % [
					_state_name(_ws_state), _state_name(new_state)
				]
			)
		_ws_state = new_state
		match _ws_state:
			WebSocketPeer.STATE_OPEN:
				_on_ws_open()
			WebSocketPeer.STATE_CLOSED:
				_on_ws_closed()

	if _ws_state == WebSocketPeer.STATE_OPEN:
		var drained := 0
		while _ws.get_available_packet_count() > 0:
			if drained >= MAX_PACKETS_PER_FRAME:
				if DEBUG_WS:
					push_warning(
						"[Network] Packet backlog: %d still queued, "
						+ "deferring" % _ws.get_available_packet_count()
					)
				break
			_handle_ws_packet(_ws.get_packet())
			drained += 1


func _on_ws_open() -> void:
	print("[Network] WebSocket connected")
	# Send an initial hello so the server can log us (optional, not required)
	_ws.send_text(JSON.stringify({
		"type": "hello",
		"client_id": "godot-main"
	}))
	connected.emit()


func _on_ws_closed() -> void:
	var code := _ws.get_close_code()
	var reason := _ws.get_close_reason()
	print("[Network] WebSocket disconnected (code=%d reason=%s)" % [code, reason])
	disconnected.emit()
	_reconnect_timer = RECONNECT_DELAY


func _handle_ws_packet(pkt: PackedByteArray) -> void:
	var text := pkt.get_string_from_utf8()
	if DEBUG_WS_TRAFFIC:
		print("[Network] IN: %s" % text)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		if DEBUG_WS:
			push_warning("[Network] non-object WS message: %s" % text)
		return
	var msg_type := str(parsed.get("type", ""))
	match msg_type:
		"server_hello":
			_handle_server_hello(parsed)
		"positions":
			_handle_positions(parsed)
		"ship_states":
			_handle_ship_states(parsed)
		"market_states":
			_handle_market_states(parsed)
		"facility_states":
			_handle_facility_states(parsed)
		"population_states":
			_handle_population_states(parsed)
		"faction_states":
			_handle_faction_states(parsed)
		"contract_states":
			_handle_contract_states(parsed)
		"events":
			_handle_events(parsed)
		"agent_state":
			_handle_agent_state(parsed)
		"sim_control_ack":
			_handle_sim_control_ack(parsed)
		_:
			if DEBUG_WS:
				push_warning("[Network] unknown message type: %s" % msg_type)


func _handle_server_hello(msg: Dictionary) -> void:
	var tick := int(msg.get("tick", 0))
	var running: bool = bool(msg.get("running", true))
	var interval := int(msg.get("interval_ms", 125))
	var count := int(msg.get("agent_count", 0))
	var ws := float(msg.get("world_speed", GameState.world_speed))
	print(
		"[Network] server_hello: tick=%d running=%s interval=%dms agents=%d ws=%.2fx"
		% [tick, running, interval, count, ws]
	)
	if GameState.has_method("update_tick"):
		GameState.update_tick(tick)
	if "tick_interval_ms" in GameState:
		GameState.tick_interval_ms = interval
	if "world_speed" in GameState:
		GameState.world_speed = ws
	# Persistent world seed — only overwrite if the server sent one
	# (pre-seed servers omit the field). Keeps the landmark layout
	# locked to whatever the DB has, including after WS reconnects.
	if msg.has("world_seed") and "world_seed" in GameState:
		GameState.world_seed = int(msg["world_seed"])


func _handle_positions(msg: Dictionary) -> void:
	var new_tick := int(msg.get("tick", 0))
	# Observed wall-clock cadence (EMA).
	var now_ms := Time.get_ticks_msec()
	if _last_positions_ms > 0:
		var gap := now_ms - _last_positions_ms
		if gap > 0 and "observed_interval_ms" in GameState:
			if GameState.observed_interval_ms > 0:
				GameState.observed_interval_ms = int(
					0.7 * GameState.observed_interval_ms + 0.3 * gap
				)
			else:
				GameState.observed_interval_ms = gap
	_last_positions_ms = now_ms

	if _last_positions_tick > 0 and "ticks_per_broadcast" in GameState:
		var tick_delta := new_tick - _last_positions_tick
		if tick_delta > 0:
			GameState.ticks_per_broadcast = tick_delta
	_last_positions_tick = new_tick

	if GameState.has_method("update_tick"):
		GameState.update_tick(new_tick)
	var interval = msg.get("interval_ms")
	if interval != null and "tick_interval_ms" in GameState:
		GameState.tick_interval_ms = int(interval)

	# Rust protocol uses "entities" with a "type" field (ship/body/facility).
	# GameState.update_positions routes by id prefix (ship-*, facility-*),
	# so pass every entity through — bodies have bare ids ("earth") which
	# fall through the prefix checks naturally.
	var entities = msg.get("entities", [])
	if entities is Array and GameState.has_method("update_positions"):
		GameState.update_positions(entities)


func _handle_ship_states(msg: Dictionary) -> void:
	var ships = msg.get("ships", [])
	if ships is Array and GameState.has_method("update_ship_states"):
		GameState.update_ship_states(ships)


func _handle_market_states(msg: Dictionary) -> void:
	var markets = msg.get("markets", [])
	if markets is Array and GameState.has_method("update_markets"):
		GameState.update_markets(markets)


func _handle_facility_states(msg: Dictionary) -> void:
	## Full facility snapshots from the facility_states WS channel.
	## Server sends every ~2s (tick % 16). Payload includes condition,
	## credits, docked_ships list, reserves, services. Godot uses
	## docked_ships.size() for its docking-glow pulse animation and
	## reserves for the details-panel tank display.
	var facilities = msg.get("facilities", [])
	if facilities is Array and GameState.has_method("update_facilities"):
		GameState.update_facilities(facilities)


func _handle_population_states(msg: Dictionary) -> void:
	## Population snapshots, every ~2s (tick % 16). Drives the population
	## browser + details panel sentiment/count fields.
	var populations = msg.get("populations", [])
	if populations is Array and GameState.has_method("update_populations_full"):
		GameState.update_populations_full(populations)


func _handle_faction_states(msg: Dictionary) -> void:
	## Faction snapshots, every ~4s (tick % 32). Carries treasury +
	## active_subsidies. Faction ledger panel renders this.
	var factions = msg.get("factions", [])
	if factions is Array and GameState.has_method("update_factions_full"):
		GameState.update_factions_full(factions)


func _handle_contract_states(msg: Dictionary) -> void:
	## Full contract board, every ~4s (tick % 32). Contract board panel
	## reads this — filter by kind/status/faction, sort by age/payment.
	var contracts = msg.get("contracts", [])
	if contracts is Array and GameState.has_method("update_contracts"):
		GameState.update_contracts(contracts)


func _handle_events(msg: Dictionary) -> void:
	## Episodic events stream. Arrives each tick when non-empty.
	## GameState appends into a ring buffer (last 200) and fires
	## `event_received` per event so panels / toasts can react.
	var tick: int = int(msg.get("tick", GameState.tick))
	var events = msg.get("events", [])
	if events is Array and GameState.has_method("append_events"):
		GameState.append_events(tick, events)


func _handle_agent_state(msg: Dictionary) -> void:
	# Reply to get_agent / get_snapshot. Apps that want to handle this
	# should look at GameState or hook via a signal.
	if DEBUG_WS:
		print("[Network] agent_state for %s" % str(msg.get("id", "")))


func _handle_sim_control_ack(msg: Dictionary) -> void:
	# Server echoes current world_speed + interval_ms on every ack so the
	# HUD label can refresh right after pause/resume/speed changes.
	if msg.has("world_speed") and "world_speed" in GameState:
		GameState.world_speed = float(msg["world_speed"])
	if msg.has("interval_ms") and "tick_interval_ms" in GameState:
		GameState.tick_interval_ms = int(msg["interval_ms"])
	print(
		"[Network] sim_control_ack: action=%s tick=%d running=%s ws=%.2fx"
		% [
			msg.get("action", "?"),
			int(msg.get("tick", 0)),
			msg.get("running", true),
			float(msg.get("world_speed", GameState.world_speed)),
		]
	)


func _state_name(s: int) -> String:
	match s:
		WebSocketPeer.STATE_OPEN: return "OPEN"
		WebSocketPeer.STATE_CONNECTING: return "CONNECTING"
		WebSocketPeer.STATE_CLOSING: return "CLOSING"
		WebSocketPeer.STATE_CLOSED: return "CLOSED"
		_: return "UNKNOWN(%d)" % s
