extends Node

## Manages HTTP requests to the simulator REST API and a native WebSocket
## connection speaking the Phoenix Channels v2 protocol directly.
##
## Phoenix v2 message format: [join_ref, ref, topic, event, payload]
##   phx_join:     [ref, ref, topic, "phx_join", {}]
##   heartbeat:    [null, ref, "phoenix", "heartbeat", {}]
##   broadcast:    [null, null, topic, event, payload]
##   client push:  [join_ref, ref, topic, event, payload]

signal connected
signal disconnected

# Host and port come from ServerManager, which resolves at connect-time
# whether we're using an external dev server or a spawned BEAM.
# These constants stay as safe fallbacks in case the autoload is missing.
const DEFAULT_BASE_URL := "http://localhost:4000"
const DEFAULT_WS_URL := "ws://localhost:4000/simulation/websocket?vsn=2.0.0"
const REFRESH_INTERVAL := 30.0  # HTTP report re-fetch cadence
const HEARTBEAT_INTERVAL := 25.0  # Server times out at 60s; send well before
const RECONNECT_DELAY := 2.0

# Debug flags — flip these to see what's happening on the wire.
# DEBUG_WS: lifecycle (connect, join, disconnect, errors)
# DEBUG_WS_TRAFFIC: every inbound/outbound message. NOISY — positions fire
# every ~125ms, so only enable when hunting a specific bug.
const DEBUG_WS := true
const DEBUG_WS_TRAFFIC := false

# WebSocket buffer sizes. Default inbound is 64 KB which is too small —
# the server's ship_states / positions broadcasts can easily exceed that,
# causing a 1009 "Message too big" close. 4 MB gives plenty of headroom
# even with hundreds of ships per payload.
const WS_INBOUND_BUFFER := 4 * 1024 * 1024
const WS_OUTBOUND_BUFFER := 1 * 1024 * 1024
const WS_MAX_QUEUED_PACKETS := 4096
# Cap how many inbound packets we process in a single frame so a backlog
# after a long alt-tab becomes a brief catch-up rather than a multi-second
# freeze. Normal peak is ~15 packets/frame at 60 fps, so 150 leaves plenty
# of headroom; a full 4096 backlog drains over ~27 frames instead of one.
const MAX_PACKETS_PER_FRAME := 150

const TOPICS := [
	"simulation:tick",
	"simulation:positions",
	"simulation:ship_states",
	"simulation:ship_events",
	"simulation:markets",
]

var _http: HTTPRequest
var _refresh_http: HTTPRequest
var _pending_callback: Callable
var _refresh_timer: float = 0.0

# WebSocket state
var _ws: WebSocketPeer
var _ws_state: int = WebSocketPeer.STATE_CLOSED
var _ref_counter: int = 0
var _heartbeat_timer: float = 0.0
var _reconnect_timer: float = -1.0
# topic -> join_ref string (so outbound pushes use the right join_ref)
var _join_refs: Dictionary = {}
# topics that have received a successful phx_reply join
var _joined_topics: Dictionary = {}

# Cadence tracking for simulation:positions broadcasts. EMA smooths a
# single dropped/delayed frame; pushed into GameState.observed_interval_ms
# so interpolation can trust wall-clock timing over the server-reported
# tick_interval_ms (which can drift when sim speed changes).
var _last_positions_ms: int = -1
var _last_positions_tick: int = -1


func _ready() -> void:
	_http = HTTPRequest.new()
	# 30s for the initial /api/report: it's a big payload and the server
	# occasionally stalls on the inner GenServer.call to Metrics. Without
	# a timeout an HTTPRequest can hang indefinitely if the server never
	# closes the connection.
	_http.timeout = 30.0
	_http.request_completed.connect(_on_http_completed)
	add_child(_http)

	_refresh_http = HTTPRequest.new()
	_refresh_http.timeout = 30.0
	_refresh_http.request_completed.connect(_on_refresh_completed)
	add_child(_refresh_http)


# -------------------- HTTP (unchanged from before) --------------------

func _base_url() -> String:
	# ServerManager is an autoload — reliable. Fallback kept for safety
	# in case someone loads this autoload without ServerManager present.
	if ServerManager != null:
		return "http://%s:%d" % [ServerManager.host(), ServerManager.port()]
	return DEFAULT_BASE_URL


func _ws_url() -> String:
	if ServerManager != null:
		return (
			"ws://%s:%d/simulation/websocket?vsn=2.0.0"
			% [ServerManager.host(), ServerManager.port()]
		)
	return DEFAULT_WS_URL


func fetch_report(callback: Callable) -> void:
	_pending_callback = callback
	var url := _base_url() + "/api/report"
	print("[Network] fetch_report → %s" % url)
	var err := _http.request(url)
	if err != OK:
		push_error("[Network] fetch_report request() rejected: %d" % err)


func post_sim_control(action: String, params: Dictionary = {}) -> void:
	var url: String
	var body: String = ""
	var headers: PackedStringArray = PackedStringArray(
		["Content-Type: application/json"]
	)

	match action:
		"pause":
			url = _base_url() + "/api/sim/pause"
		"resume":
			url = _base_url() + "/api/sim/resume"
		"set_speed":
			url = _base_url() + "/api/sim/speed"
			body = JSON.stringify(params)
		_:
			push_warning("Unknown sim control action: " + action)
			return

	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(_r, _c, _h, _b): req.queue_free()
	)
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
			# Small bodies are likely error JSON from the server — log it.
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
	GameState.refresh_world_data(json)


func disconnect_ws() -> void:
	# Cleanly tear down the WebSocket and cancel pending reconnects.
	# Called when we're about to return to the main menu so we don't
	# keep retrying against a dead server.
	if _ws != null:
		_ws.close(1000, "client disconnect")
	_reconnect_timer = -1.0
	_joined_topics.clear()
	_join_refs.clear()


# -------------------- Admin / god-mode HTTP --------------------
#
# Callback signature: (response_code: int, body_text: String) -> void
# Each call spawns a one-shot HTTPRequest that queue_frees on completion.

func admin_create_ship(data: Dictionary, cb: Callable) -> void:
	_admin_request(HTTPClient.METHOD_POST, "/api/admin/ships", data, cb)


func admin_destroy_ship(ship_id: String, cb: Callable) -> void:
	_admin_request(
		HTTPClient.METHOD_DELETE, "/api/admin/ships/" + ship_id, null, cb
	)


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
	# Server uses the location slug (e.g. "earth-station") not the
	# facility_id ("facility-earth-station") in this path.
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
	# IMPORTANT: buffer sizes must be set BEFORE connect_to_url
	_ws.inbound_buffer_size = WS_INBOUND_BUFFER
	_ws.outbound_buffer_size = WS_OUTBOUND_BUFFER
	_ws.max_queued_packets = WS_MAX_QUEUED_PACKETS
	var url := _ws_url()
	var err: int = _ws.connect_to_url(url)
	if err != OK:
		push_error(
			"[Network] WebSocket connect_to_url failed: %d" % err
		)
		_reconnect_timer = RECONNECT_DELAY
		return
	if DEBUG_WS:
		print("[Network] WebSocket connecting to %s..." % url)


func send_move_observer(id: String, x: float, y: float) -> void:
	var topic := "simulation:tick"
	if _ws_state != WebSocketPeer.STATE_OPEN:
		return
	if not _joined_topics.has(topic):
		return
	var join_ref: String = _join_refs.get(topic, "")
	var ref := _next_ref()
	var msg := [
		join_ref, ref, topic, "move_observer",
		{"id": id, "x": x, "y": y}
	]
	_ws.send_text(JSON.stringify(msg))


func _process(delta: float) -> void:
	# HTTP report refresh
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
	var new_state: int = _ws.get_ready_state()

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
		_heartbeat_timer += delta
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_send_heartbeat()
		var drained: int = 0
		while _ws.get_available_packet_count() > 0:
			if drained >= MAX_PACKETS_PER_FRAME:
				if DEBUG_WS:
					push_warning(
						"[Network] Packet backlog: %d still queued, deferring to next frame"
						% _ws.get_available_packet_count()
					)
				break
			_handle_ws_packet(_ws.get_packet())
			drained += 1


func _on_ws_open() -> void:
	print("[Network] WebSocket connected")
	_heartbeat_timer = 0.0
	_join_refs.clear()
	_joined_topics.clear()
	for topic in TOPICS:
		_join_topic(topic)
	# Factions are loaded from /api/report before connect_websocket, so
	# they're already in GameState by the time we get here. Subscribe to
	# each one for subsidy_posted notifications.
	for faction_slug in GameState.factions.keys():
		_join_topic("simulation:faction:%s" % str(faction_slug))
	connected.emit()


func _on_ws_closed() -> void:
	var code: int = _ws.get_close_code()
	var reason: String = _ws.get_close_reason()
	print(
		"[Network] WebSocket disconnected (code=%d reason=%s)" % [
			code, reason
		]
	)
	_join_refs.clear()
	_joined_topics.clear()
	disconnected.emit()
	_reconnect_timer = RECONNECT_DELAY


func _next_ref() -> String:
	_ref_counter += 1
	return str(_ref_counter)


func _join_topic(topic: String) -> void:
	var ref := _next_ref()
	_join_refs[topic] = ref
	var msg := [ref, ref, topic, "phx_join", {}]
	var text := JSON.stringify(msg)
	if DEBUG_WS:
		print("[Network] -> phx_join %s" % topic)
	if DEBUG_WS_TRAFFIC:
		print("[Network] OUT: %s" % text)
	_ws.send_text(text)


func _send_heartbeat() -> void:
	var ref := _next_ref()
	var msg: Array = [null, ref, "phoenix", "heartbeat", {}]
	var text := JSON.stringify(msg)
	if DEBUG_WS_TRAFFIC:
		print("[Network] OUT: %s" % text)
	_ws.send_text(text)


func _handle_ws_packet(pkt: PackedByteArray) -> void:
	var text: String = pkt.get_string_from_utf8()
	if DEBUG_WS_TRAFFIC:
		print("[Network] IN:  %s" % text)
	var parsed = JSON.parse_string(text)
	if not (parsed is Array) or parsed.size() < 5:
		if DEBUG_WS:
			push_warning(
				"[Network] Unexpected packet shape: %s" % text
			)
		return
	var topic: String = str(parsed[2])
	var event: String = str(parsed[3])
	var payload = parsed[4]
	_dispatch(topic, event, payload)


func _state_name(s: int) -> String:
	match s:
		WebSocketPeer.STATE_OPEN: return "OPEN"
		WebSocketPeer.STATE_CONNECTING: return "CONNECTING"
		WebSocketPeer.STATE_CLOSING: return "CLOSING"
		WebSocketPeer.STATE_CLOSED: return "CLOSED"
		_: return "UNKNOWN(%d)" % s


func _dispatch(topic: String, event: String, payload) -> void:
	# Join / heartbeat replies
	if event == "phx_reply":
		if payload is Dictionary:
			var status: String = str(payload.get("status", ""))
			if status == "ok" and topic != "phoenix":
				if not _joined_topics.has(topic):
					_joined_topics[topic] = true
					print("[Network] Joined %s" % topic)
			elif status == "error":
				push_warning(
					"[Network] Reply error on %s: %s" % [
						topic, str(payload.get("response", ""))
					]
				)
		return

	if event == "phx_error" or event == "phx_close":
		push_warning(
			"[Network] Channel %s got %s — %s" % [topic, event, str(payload)]
		)
		_joined_topics.erase(topic)
		return

	if not (payload is Dictionary):
		return

	match topic:
		"simulation:tick":
			if event == "tick":
				GameState.update_tick(int(payload.get("tick", 0)))
		"simulation:positions":
			if event == "positions":
				var new_tick: int = int(payload.get("tick", 0))
				# Observed wall-clock gap between broadcasts (EMA).
				var now_ms: int = Time.get_ticks_msec()
				if _last_positions_ms > 0:
					var gap: int = now_ms - _last_positions_ms
					if gap > 0:
						if GameState.observed_interval_ms > 0:
							GameState.observed_interval_ms = int(
								0.7 * GameState.observed_interval_ms
								+ 0.3 * gap
							)
						else:
							GameState.observed_interval_ms = gap
				_last_positions_ms = now_ms
				# Ticks elapsed per broadcast — diagnostic signal for
				# whether the server is batching or broadcasting per-tick.
				if _last_positions_tick > 0:
					var tick_delta: int = new_tick - _last_positions_tick
					if tick_delta > 0:
						GameState.ticks_per_broadcast = tick_delta
				_last_positions_tick = new_tick

				GameState.update_tick(new_tick)
				var interval = payload.get("interval_ms")
				if interval != null:
					GameState.tick_interval_ms = int(interval)
				var ships_array = payload.get("ships", [])
				if ships_array is Array:
					GameState.update_positions(ships_array)
		"simulation:ship_states":
			if event == "ship_states" or event == "states":
				var ships_array = payload.get("ships", [])
				if ships_array is Array:
					GameState.update_ship_states(ships_array)
		"simulation:ship_events":
			GameState.handle_ship_event(event, payload)
		"simulation:markets":
			if event == "market_states" or event == "markets":
				var markets_array = payload.get("markets", [])
				if markets_array is Array:
					GameState.update_markets(markets_array)
		_:
			# Dynamic per-faction topic (simulation:faction:<slug>)
			if topic.begins_with("simulation:faction:"):
				if event == "subsidy_posted":
					GameState.handle_subsidy_posted(payload)
