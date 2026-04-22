extends PanelContainer

## Compact performance readout for Phase 13d. Shows:
##   * tick compute p50 / p99 from GameState.tick_compute_{p50,p99}_us
##   * client FPS
##   * last-60 observed positions-broadcast intervals vs. reported
##   * last-60 tick durations plotted as a sparkline (visual hitch detector)
##
## Data source: `/api/report` refresh updates GameState perf fields;
## FPS + interval EMA come from Engine + NetworkManager already.

@onready var p50_label: Label = $VBox/Grid/P50Value
@onready var p99_label: Label = $VBox/Grid/P99Value
@onready var fps_label: Label = $VBox/Grid/FPSValue
@onready var tps_label: Label = $VBox/Grid/TPSValue
@onready var interval_label: Label = $VBox/Grid/IntervalValue
@onready var lod_label: Label = $VBox/Grid/LodValue
@onready var sparkline: Control = $VBox/Sparkline
@onready var close_button: Button = $VBox/TopRow/CloseButton

const SPARKLINE_SAMPLES := 60
## Poll /api/health while the perf panel is visible — the main
## /api/report refresh runs every 30s which is too slow for a live
## HUD. 1s keeps the display responsive without hammering the server.
const HEALTH_POLL_SEC := 1.0

var _sparkline_samples: PackedFloat32Array = PackedFloat32Array()
var _health_timer: float = 0.0
var _health_http: HTTPRequest


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	sparkline.draw.connect(_draw_sparkline)
	_sparkline_samples.resize(SPARKLINE_SAMPLES)
	_health_http = HTTPRequest.new()
	add_child(_health_http)
	_health_http.request_completed.connect(_on_health_response)


func toggle() -> void:
	visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	# Poll /api/health on a 1s cadence while the panel is open so the
	# live perf + LOD values don't drift 30s stale with the main report.
	_health_timer -= _delta
	if _health_timer <= 0.0:
		_health_timer = HEALTH_POLL_SEC
		_poll_health()

	var p50: int = GameState.tick_compute_p50_us
	var p99: int = GameState.tick_compute_p99_us
	p50_label.text = _fmt_us(p50)
	p99_label.text = _fmt_us(p99)
	if p50 > 5_000:
		p50_label.add_theme_color_override("font_color", ThemePalette.WARN)
	else:
		p50_label.remove_theme_color_override("font_color")
	if p99 > 20_000:
		p99_label.add_theme_color_override("font_color", ThemePalette.DANGER)
	elif p99 > 10_000:
		p99_label.add_theme_color_override("font_color", ThemePalette.WARN)
	else:
		p99_label.remove_theme_color_override("font_color")

	fps_label.text = "%d" % Engine.get_frames_per_second()
	tps_label.text = "%d" % GameState.ticks_per_broadcast
	# observed_interval_ms vs reported tick_interval_ms — divergence ≈ lag
	if GameState.observed_interval_ms > 0:
		interval_label.text = "%d ms (rpt %d)" % [
			GameState.observed_interval_ms, GameState.tick_interval_ms
		]
	else:
		interval_label.text = "%d ms" % GameState.tick_interval_ms

	# LOD tier distribution — compact "d1/d2/d5/d10/d20/d50" readout.
	# Zero-count tiers get dim text so the eye jumps to active ones.
	var parts: PackedStringArray = PackedStringArray()
	var any_throttled := (
		GameState.lod_d2 + GameState.lod_d5 + GameState.lod_d10
		+ GameState.lod_d20 + GameState.lod_d50
	) > 0
	parts.append(_lod_chip("d1", GameState.lod_d1, not any_throttled))
	parts.append(_lod_chip("d2", GameState.lod_d2, false))
	parts.append(_lod_chip("d5", GameState.lod_d5, false))
	parts.append(_lod_chip("d10", GameState.lod_d10, false))
	parts.append(_lod_chip("d20", GameState.lod_d20, false))
	parts.append(_lod_chip("d50", GameState.lod_d50, false))
	lod_label.text = " ".join(parts)

	# Shift a new sample in each frame (dedup via the fact that redraw
	# happens at frame rate — this gives a sense of tick-smoothness).
	_push_sample(float(p99))
	sparkline.queue_redraw()


func _push_sample(v: float) -> void:
	# Scroll-left via slice + append; small enough that the allocation is fine.
	for i in range(_sparkline_samples.size() - 1):
		_sparkline_samples[i] = _sparkline_samples[i + 1]
	_sparkline_samples[_sparkline_samples.size() - 1] = v


func _draw_sparkline() -> void:
	var sz := sparkline.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	# Background
	sparkline.draw_rect(
		Rect2(Vector2.ZERO, sz),
		ThemePalette.PANEL_BG,
		true
	)
	var max_v := 1.0
	for v in _sparkline_samples:
		if v > max_v:
			max_v = v
	var step_x: float = sz.x / float(max(_sparkline_samples.size() - 1, 1))
	var prev := Vector2(0.0, sz.y - (_sparkline_samples[0] / max_v) * sz.y)
	for i in range(1, _sparkline_samples.size()):
		var p := Vector2(
			step_x * i,
			sz.y - (_sparkline_samples[i] / max_v) * sz.y
		)
		sparkline.draw_line(prev, p, ThemePalette.PRIMARY, 1.5)
		prev = p
	# Budget line: red at the 125 ms tick budget (in µs).
	var budget := 125_000.0
	if max_v > 0.0:
		var budget_y: float = sz.y - (budget / max_v) * sz.y
		if budget_y > 0.0 and budget_y < sz.y:
			sparkline.draw_line(
				Vector2(0, budget_y),
				Vector2(sz.x, budget_y),
				Color(ThemePalette.DANGER, 0.6),
				1.0
			)


## Format one LOD tier like "d5:42". Empty tiers render as "-" so the
## row doesn't visually clutter. `active` = the only non-zero tier and
## nothing's throttled — render bright.
func _lod_chip(name: String, count: int, _active: bool) -> String:
	if count <= 0:
		return "%s:-" % name
	return "%s:%d" % [name, count]


func _poll_health() -> void:
	if _health_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		# Already in-flight — skip this round rather than queueing.
		return
	var url := NetworkManager._base_url() + "/api/health"
	_health_http.request(url)


func _on_health_response(
	_result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray
) -> void:
	if response_code != 200 or body.size() == 0:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var perf: Dictionary = parsed.get("perf", {})
	if perf.size() == 0:
		return
	GameState.tick_compute_p50_us = int(
		perf.get("tick_compute_p50_us", GameState.tick_compute_p50_us)
	)
	GameState.tick_compute_p99_us = int(
		perf.get("tick_compute_p99_us", GameState.tick_compute_p99_us)
	)
	var lod: Dictionary = perf.get("lod", {})
	if lod.size() > 0:
		GameState.lod_d1 = int(lod.get("d1", 0))
		GameState.lod_d2 = int(lod.get("d2", 0))
		GameState.lod_d5 = int(lod.get("d5", 0))
		GameState.lod_d10 = int(lod.get("d10", 0))
		GameState.lod_d20 = int(lod.get("d20", 0))
		GameState.lod_d50 = int(lod.get("d50", 0))


func _fmt_us(us: int) -> String:
	if us >= 10_000:
		return "%.1f ms" % (float(us) / 1000.0)
	if us >= 1_000:
		return "%.2f ms" % (float(us) / 1000.0)
	return "%d µs" % us
