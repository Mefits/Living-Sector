extends Node3D

## Main scene controller. Bootstraps the world by fetching the simulator report,
## building the visual world, then connecting the WebSocket for live updates.

@onready var universe: Node3D = $Universe
@onready var camera: Camera3D = $GameCamera
@onready var hud: CanvasLayer = $HUD

var _transit_lines_script: GDScript = preload(
	"res://scripts/world/transit_lines.gd"
)
var _observer_scene: PackedScene = preload(
	"res://scenes/world/observer.tscn"
)
var _details_panel_scene: PackedScene = preload(
	"res://scenes/ui/details_panel.tscn"
)
var _selection_ring_script: GDScript = preload(
	"res://scripts/world/selection_ring.gd"
)
var _starfield_script: GDScript = preload(
	"res://scripts/world/starfield.gd"
)
var _context_menu_script: GDScript = preload(
	"res://scripts/ui/context_menu.gd"
)
var _ship_list_scene: PackedScene = preload(
	"res://scenes/ui/ship_list.tscn"
)
var _market_overlay_scene: PackedScene = preload(
	"res://scenes/ui/market_overlay.tscn"
)
var _god_toolbar_scene: PackedScene = preload(
	"res://scenes/ui/god_toolbar.tscn"
)
var _add_ship_panel_scene: PackedScene = preload(
	"res://scenes/ui/add_ship_panel.tscn"
)
var _add_facility_panel_scene: PackedScene = preload(
	"res://scenes/ui/add_facility_panel.tscn"
)
var _facility_reserves_panel_scene: PackedScene = preload(
	"res://scenes/ui/facility_reserves_panel.tscn"
)
# Phase 13 debug panels
var _events_ticker_scene: PackedScene = preload(
	"res://scenes/ui/events_ticker.tscn"
)
var _contract_board_scene: PackedScene = preload(
	"res://scenes/ui/contract_board.tscn"
)
var _faction_ledger_scene: PackedScene = preload(
	"res://scenes/ui/faction_ledger.tscn"
)
var _population_browser_scene: PackedScene = preload(
	"res://scenes/ui/population_browser.tscn"
)
var _perf_overlay_scene: PackedScene = preload(
	"res://scenes/ui/perf_overlay.tscn"
)
var _destroy_hover_script: GDScript = preload(
	"res://scripts/ui/destroy_hover_indicator.gd"
)

var _observer: Node3D
var _details_panel: Control
var _context_menu: PopupMenu
var _ship_list: Control
var _market_overlay: Control
var _god_toolbar: Control
var _add_ship_panel: Control
var _add_facility_panel: Control
var _facility_reserves_panel: Control
var _events_ticker: Control
var _contract_board: Control
var _faction_ledger: Control
var _population_browser: Control
var _perf_overlay: Control
var _destroy_hover: Control
var _toast: VBoxContainer
var _selection_ring: MeshInstance3D
var _selected_node: Node3D  # The 3D node we're following
var _observer_active := false
# God-mode: when true, left-clicks on ships/facilities in the viewport
# trigger the stub destroy instead of normal selection. Cursor becomes
# the forbidden-circle. ESC or re-pressing the toolbar button exits.
var _destroy_mode := false
var _send_timer: float = 0.0
const SEND_INTERVAL := 0.05

# "Flight recorder": hitch detector + periodic state heartbeat. When the
# client freezes with no console output, the LAST heartbeat before the
# freeze is the best clue we have about what state was live. Slow-frame
# warnings catch smaller hitches that do NOT freeze the app so we can
# find performance cliffs before they become crashes.
const RECORDER_ENABLED := true
const SLOW_FRAME_SEC := 0.1      # ≥ 100 ms frame gets logged
const HEARTBEAT_INTERVAL := 10.0 # log a state snapshot every ~10s
var _heartbeat_timer: float = 0.0


func _ready() -> void:
  print("[Main] Fetching world snapshot...")
  NetworkManager.fetch_report(_on_report_loaded)


func _on_report_loaded(data: Dictionary) -> void:
  print("[Main] Report loaded — tick %d, %d ships, %d facilities" % [
    data.get("tick", 0),
    data.get("ships", []).size(),
    data.get("facilities", []).size(),
  ])

  GameState.load_world_snapshot(data)
  universe.set_camera(camera)

  # Parallax starfield background
  var starfield := Node3D.new()
  starfield.set_script(_starfield_script)
  add_child(starfield)
  starfield.setup(camera)

  universe.build_world()

  # Transit lines
  var transit_lines := MeshInstance3D.new()
  transit_lines.set_script(_transit_lines_script)
  universe.add_child(transit_lines)

  # Observer
  _observer = _observer_scene.instantiate()
  universe.add_child(_observer)
  var observers: Array = data.get("observers", [])
  var obs_x := 0.0
  var obs_y := 0.0
  var obs_id := "default"
  if observers.size() > 0:
    var obs: Dictionary = observers[0]
    obs_id = obs.get("id", "default")
    obs_x = float(obs.get("x", 0.0))
    obs_y = float(obs.get("y", 0.0))
  _observer.setup(obs_id, obs_x, obs_y)
  _observer.position_changed.connect(_on_observer_moved)

  # Selection ring (reusable, reparented to selected node)
  _selection_ring = MeshInstance3D.new()
  _selection_ring.set_script(_selection_ring_script)
  _selection_ring.visible = false
  add_child(_selection_ring)

  # Details panel
  _details_panel = _details_panel_scene.instantiate()
  hud.add_child(_details_panel)
  _details_panel.anchors_preset = Control.PRESET_TOP_LEFT
  _details_panel.position = Vector2(10, 40)

  # Context menu
  _context_menu = PopupMenu.new()
  _context_menu.set_script(_context_menu_script)
  hud.add_child(_context_menu)
  _context_menu.action_selected.connect(_on_context_action)

  # Ship list panel (right side)
  _ship_list = _ship_list_scene.instantiate()
  hud.add_child(_ship_list)
  _ship_list.anchor_left = 1.0
  _ship_list.anchor_right = 1.0
  _ship_list.anchor_top = 0.0
  _ship_list.anchor_bottom = 1.0
  _ship_list.offset_left = -460.0
  _ship_list.offset_top = 40.0
  _ship_list.offset_right = -10.0
  _ship_list.offset_bottom = -200.0
  _ship_list.ship_selected.connect(_on_ship_list_selected)
  _ship_list.location_selected.connect(_on_location_selected)
  hud.ship_list_toggled.connect(func(): _ship_list.toggle())

  # Market panel (nearly full screen, centered)
  _market_overlay = _market_overlay_scene.instantiate()
  hud.add_child(_market_overlay)
  _market_overlay.anchor_left = 0.05
  _market_overlay.anchor_right = 0.95
  _market_overlay.anchor_top = 0.05
  _market_overlay.anchor_bottom = 0.95
  _market_overlay.offset_left = 0.0
  _market_overlay.offset_right = 0.0
  _market_overlay.offset_top = 0.0
  _market_overlay.offset_bottom = 0.0
  hud.market_toggled.connect(func(): _market_overlay.toggle())

  # --- Phase 13 inspector panels ---
  # Contract board (near-fullscreen, like market overlay)
  _contract_board = _contract_board_scene.instantiate()
  hud.add_child(_contract_board)
  _contract_board.anchor_left = 0.05
  _contract_board.anchor_right = 0.95
  _contract_board.anchor_top = 0.08
  _contract_board.anchor_bottom = 0.92
  hud.contracts_toggled.connect(func(): _contract_board.toggle())
  _contract_board.contract_selected.connect(_on_contract_selected)

  # Faction ledger (right side, above ship list)
  _faction_ledger = _faction_ledger_scene.instantiate()
  hud.add_child(_faction_ledger)
  _faction_ledger.anchor_left = 1.0
  _faction_ledger.anchor_right = 1.0
  _faction_ledger.anchor_top = 0.0
  _faction_ledger.offset_left = -580.0
  _faction_ledger.offset_top = 40.0
  _faction_ledger.offset_right = -10.0
  _faction_ledger.offset_bottom = 360.0
  hud.factions_toggled.connect(func(): _faction_ledger.toggle())

  # Population browser (right side, mid)
  _population_browser = _population_browser_scene.instantiate()
  hud.add_child(_population_browser)
  _population_browser.anchor_left = 1.0
  _population_browser.anchor_right = 1.0
  _population_browser.anchor_top = 0.0
  _population_browser.offset_left = -640.0
  _population_browser.offset_top = 40.0
  _population_browser.offset_right = -10.0
  _population_browser.offset_bottom = 440.0
  hud.pops_toggled.connect(func(): _population_browser.toggle())

  # Events ticker (bottom-right, narrow)
  _events_ticker = _events_ticker_scene.instantiate()
  hud.add_child(_events_ticker)
  _events_ticker.anchor_left = 1.0
  _events_ticker.anchor_right = 1.0
  _events_ticker.anchor_top = 1.0
  _events_ticker.anchor_bottom = 1.0
  _events_ticker.offset_left = -540.0
  _events_ticker.offset_top = -440.0
  _events_ticker.offset_right = -10.0
  _events_ticker.offset_bottom = -210.0
  hud.events_toggled.connect(func(): _events_ticker.toggle())
  _events_ticker.focus_requested.connect(_on_focus_requested)

  # Perf overlay (top-right-ish, below speed buttons)
  _perf_overlay = _perf_overlay_scene.instantiate()
  hud.add_child(_perf_overlay)
  _perf_overlay.anchor_left = 1.0
  _perf_overlay.anchor_right = 1.0
  _perf_overlay.anchor_top = 0.0
  _perf_overlay.offset_left = -320.0
  _perf_overlay.offset_top = 50.0
  _perf_overlay.offset_right = -10.0
  _perf_overlay.offset_bottom = 170.0
  hud.perf_toggled.connect(func(): _perf_overlay.toggle())

  # Step-debug wiring
  hud.step_requested.connect(_on_step_requested)

  # God-mode toolbar (bottom-left)
  _god_toolbar = _god_toolbar_scene.instantiate()
  hud.add_child(_god_toolbar)
  _god_toolbar.anchor_left = 0.0
  _god_toolbar.anchor_right = 0.0
  _god_toolbar.anchor_top = 1.0
  _god_toolbar.anchor_bottom = 1.0
  _god_toolbar.offset_left = 10.0
  _god_toolbar.offset_top = -60.0
  _god_toolbar.offset_bottom = -10.0
  _god_toolbar.destroy_toggled.connect(_on_destroy_toggled)
  _god_toolbar.add_ship_pressed.connect(_on_add_ship_pressed)
  _god_toolbar.add_facility_pressed.connect(_on_add_facility_pressed)

  # God-mode forms (centered overlays, hidden until opened)
  _add_ship_panel = _add_ship_panel_scene.instantiate()
  hud.add_child(_add_ship_panel)
  _add_ship_panel.anchor_left = 0.5
  _add_ship_panel.anchor_right = 0.5
  _add_ship_panel.anchor_top = 0.5
  _add_ship_panel.anchor_bottom = 0.5
  _add_ship_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
  _add_ship_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
  _add_ship_panel.create_requested.connect(_on_create_ship_requested)

  _add_facility_panel = _add_facility_panel_scene.instantiate()
  hud.add_child(_add_facility_panel)
  _add_facility_panel.anchor_left = 0.5
  _add_facility_panel.anchor_right = 0.5
  _add_facility_panel.anchor_top = 0.5
  _add_facility_panel.anchor_bottom = 0.5
  _add_facility_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
  _add_facility_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
  _add_facility_panel.create_requested.connect(_on_create_facility_requested)

  _facility_reserves_panel = _facility_reserves_panel_scene.instantiate()
  hud.add_child(_facility_reserves_panel)
  _facility_reserves_panel.anchor_left = 0.5
  _facility_reserves_panel.anchor_right = 0.5
  _facility_reserves_panel.anchor_top = 0.5
  _facility_reserves_panel.anchor_bottom = 0.5
  _facility_reserves_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
  _facility_reserves_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
  _facility_reserves_panel.apply_requested.connect(
    _on_reserves_apply_requested
  )

  # Destroy-mode hover indicator (a red ring control we move around
  # the HUD layer under the mouse). Hidden by default.
  _destroy_hover = Control.new()
  _destroy_hover.set_script(_destroy_hover_script)
  hud.add_child(_destroy_hover)

  # Toast notifications (bottom-center)
  _toast = VBoxContainer.new()
  _toast.set_script(
    preload("res://scripts/ui/toast.gd")
  )
  hud.add_child(_toast)
  _toast.anchor_left = 0.5
  _toast.anchor_right = 0.5
  _toast.anchor_top = 1.0
  _toast.anchor_bottom = 1.0
  _toast.offset_left = -200.0
  _toast.offset_right = 200.0
  _toast.offset_top = -120.0
  _toast.offset_bottom = -40.0
  _toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
  GameState.toast_requested.connect(_toast.show_toast)

  # Minimap
  var minimap: Control = hud.find_child("Minimap")
  if minimap:
    minimap.set_camera(camera)

  # HUD signals
  hud.observer_toggled.connect(_on_observer_toggled)

  # Clean up selection when a ship is decommissioned
  GameState.ship_removed.connect(_on_ship_removed)
  GameState.facility_removed.connect(_on_facility_removed)

  # If the bundled simulator dies mid-session, return to the main menu.
  # Skipped when we're using an external dev server (those restarts
  # are routine — the WS will reconnect on its own).
  ServerManager.server_died.connect(_on_server_died)

  camera.focus_on(Vector3.ZERO)

  GameState.show_toast(
    "World loaded: %d ships, %d facilities" % [
      GameState.ships.size(),
      GameState.facilities.size()
    ],
    ThemePalette.PRIMARY
  )

  print("[Main] Connecting WebSocket...")
  NetworkManager.connect_websocket()


func _on_observer_toggled(active: bool) -> void:
  _observer_active = active
  _observer.set_active(active)
  if active:
    # Observer mode — clear entity selection, follow observer.
    # Exit POV first if we're in it (the two modes don't mix).
    if camera.pov_target:
      camera.exit_pov()
    _clear_selection()
    camera.follow_target = _observer
    camera.zoom_level = 30.0
    camera.position.y = camera.zoom_level
  else:
    camera.follow_target = null


func _on_observer_moved(_x: float, _y: float) -> void:
  _send_timer = SEND_INTERVAL


func _process(delta: float) -> void:
  if _send_timer > 0.0:
    _send_timer -= delta
    if _send_timer <= 0.0:
      # Always send a "camera" observer so the Rust spatial-LOD pass
      # knows where the viewport is. Explicit Observer-mode still sends
      # its own entry on top, but this one covers the common case of
      # the user panning around without activating an observer. Radius
      # scales with zoom — zoomed out = bigger attention volume.
      var cam_universe_x: float = camera.position.x / GameState.SCALE_FACTOR
      var cam_universe_y: float = camera.position.z / GameState.SCALE_FACTOR
      var cam_radius: float = maxf(
        5.0, GameState.zoom_raw / GameState.SCALE_FACTOR * 1.5
      )
      NetworkManager.send_move_observer(
        "camera", cam_universe_x, cam_universe_y, cam_radius
      )
      if _observer_active and _observer:
        var upos: Vector2 = _observer.get_universe_position()
        NetworkManager.send_move_observer(
          _observer.observer_id, upos.x, upos.y
        )
      _send_timer = SEND_INTERVAL

  # Keep camera following the selected entity (ships move)
  if _selected_node and not _observer_active:
    camera.follow_target = _selected_node

  # Destroy-mode hover ring / cursor
  if _destroy_mode and _destroy_hover:
    _update_destroy_hover()

  if RECORDER_ENABLED:
    # Slow-frame breadcrumb: any frame ≥ 100 ms leaves a note with
    # live state. If the app later freezes, the last few of these
    # tell us what was expensive leading up to it.
    if delta >= SLOW_FRAME_SEC:
      print(
        "[Recorder] slow frame %.0f ms — %s" % [
          delta * 1000.0, _state_snapshot()
        ]
      )
    # Periodic heartbeat even on healthy frames so a freeze with NO
    # slow-frame warning still leaves a final "last state seen" line.
    _heartbeat_timer += delta
    if _heartbeat_timer >= HEARTBEAT_INTERVAL:
      _heartbeat_timer = 0.0
      print("[Recorder] heartbeat — %s" % _state_snapshot())


func _state_snapshot() -> String:
  var details_open: bool = (
    _details_panel != null and _details_panel.visible
  )
  var ship_list_open: bool = (
    _ship_list != null and _ship_list.visible
  )
  var market_open: bool = (
    _market_overlay != null and _market_overlay.visible
  )
  var toast_count: int = (
    _toast.get_child_count() if _toast != null else 0
  )
  var pov_on: bool = camera != null and camera.pov_target != null
  return (
    (
			"tick=%d ships=%d fac=%d mkt=%d fac_sel=%s pov=%s obs=%s "
      + "panels=[d=%s l=%s m=%s] toasts=%d nodes=%d mem=%dKB "
      + "fps=%d report=%d observed=%d ticks/bc=%d"
    )
    % [
      GameState.tick,
      GameState.ships.size(),
      GameState.facilities.size(),
      GameState.markets.size(),
      GameState.selected_entity_id,
      str(pov_on),
      str(_observer_active),
      str(details_open),
      str(ship_list_open),
      str(market_open),
      toast_count,
      Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
      int(
        Performance.get_monitor(Performance.MEMORY_STATIC)
        / 1024.0
      ),
      int(Performance.get_monitor(Performance.TIME_FPS)),
      GameState.tick_interval_ms,
      GameState.observed_interval_ms,
      GameState.ticks_per_broadcast,
    ]
  )


func _unhandled_input(event: InputEvent) -> void:
  # ESC cancels destroy mode before anything else can consume it.
  if _destroy_mode and event is InputEventKey:
    if event.pressed and event.keycode == KEY_ESCAPE:
      _exit_destroy_mode()
      get_viewport().set_input_as_handled()
      return

  if event is InputEventMouseButton and event.pressed:
    if event.button_index == MOUSE_BUTTON_LEFT:
      _handle_click(event.position)
    elif event.button_index == MOUSE_BUTTON_RIGHT:
      _handle_right_click(event.position)


class EntityHit:
  var id: String = ""
  var type: String = ""
  var sys_id: String = ""


const SCREEN_HIT_RADIUS_PX := 28.0
# Bodies are chunky on screen, so a more generous radius reads better.
const BODY_HIT_RADIUS_PX := 48.0


func _find_nearest_entity(screen_pos: Vector2) -> EntityHit:
  # Screen-space pixel distance from the click to each entity's
  # projected 2D position. "Clicking on" something means the click
  # lands within N pixels of its on-screen dot — matches visual
  # reality at any zoom, naturally rejects empty-space clicks.
  var hit := EntityHit.new()
  var best_entity_dist: float = SCREEN_HIT_RADIUS_PX
  var best_body_dist: float = BODY_HIT_RADIUS_PX

  for ship_data in GameState.ships.values():
    var pos = ship_data.get("position", {})
    if not (pos is Dictionary):
      continue
    var world := GameState.server_to_world(
      float(pos.get("x", 0.0)), float(pos.get("y", 0.0))
    )
    if camera.is_position_behind(world):
      continue
    var dist: float = camera.unproject_position(world).distance_to(
      screen_pos
    )
    if dist < best_entity_dist:
      best_entity_dist = dist
      hit.id = ship_data.get("id", "")
      hit.type = "ship"
      hit.sys_id = ""

  for fac_data in GameState.facilities.values():
    var pos = fac_data.get("position", {})
    if not (pos is Dictionary):
      continue
    var fx: float = float(pos.get("x", 0.0))
    var fy: float = float(pos.get("y", 0.0))
    if fx == 0.0 and fy == 0.0:
      continue
    var world := GameState.server_to_world(fx, fy)
    if camera.is_position_behind(world):
      continue
    var dist: float = camera.unproject_position(world).distance_to(
      screen_pos
    )
    if dist < best_entity_dist:
      best_entity_dist = dist
      hit.id = fac_data.get("id", "")
      hit.type = "facility"
      hit.sys_id = ""

  # Bodies last — only wins if no ship or facility was hit, since
  # ships/facilities should take priority when they sit in front of
  # a planet.
  if hit.id == "":
    for sys_data in GameState.systems.values():
      for body in sys_data.get("bodies", []):
        var bx = body.get("x")
        var by = body.get("y")
        if bx == null or by == null:
          continue
        var world := GameState.server_to_world(float(bx), float(by))
        if camera.is_position_behind(world):
          continue
        var dist: float = camera.unproject_position(
          world
        ).distance_to(screen_pos)
        if dist < best_body_dist:
          best_body_dist = dist
          hit.id = body.get("id", "")
          hit.type = "body"
          hit.sys_id = sys_data.get("id", "")

  return hit


func _handle_click(screen_pos: Vector2) -> void:
  # God-mode destroy: left-click on a ship/facility deletes it (stub)
  # and stays in the mode for rapid-fire. Only ships and facilities
  # are valid targets — clicking empty space / a body is a no-op.
  if _destroy_mode:
    var destroy_hit := _find_nearest_entity(screen_pos)
    if destroy_hit.id != "":
      var t: String = destroy_hit.type
      if t == "ship" or t == "facility":
        _god_destroy_entity(destroy_hit.id, t)
    return

  # While the details panel is open, any click in the 3D viewport
  # dismisses it instead of picking a new entity — avoids the "tried
  # to close the panel, accidentally selected something else" trap.
  if _details_panel and _details_panel.is_selecting():
    _clear_selection()
    return

  var hit := _find_nearest_entity(screen_pos)
  if hit.id != "":
    _select_entity(hit.id, hit.type, hit.sys_id)
  else:
    _clear_selection()


func _select_entity(
  id: String, type: String, sys_id: String
) -> void:
  GameState.selected_entity_id = id
  # Selection chime — gentle click so the player gets audible feedback
  # that their click registered. Skipped when the same entity is
  # re-selected to avoid double-taps spamming the sound.
  var audio: Node = get_node_or_null(^"/root/ProceduralAudio")
  if audio and audio.has_method(&"play_select"):
    audio.call(&"play_select")
  # Show details panel
  match type:
    "ship":
      _details_panel.select_ship(id)
    "facility":
      _details_panel.select_facility(id)
    "body":
      _details_panel.select_body(sys_id, id)

  # Find the 3D node and attach selection ring
  var node: Node3D = _find_entity_node(id, type)
  if node:
    _selected_node = node

    # Reparent ring to selected node
    if _selection_ring.get_parent():
      _selection_ring.get_parent().remove_child(_selection_ring)
    node.add_child(_selection_ring)
    _selection_ring.position = Vector3.ZERO
    _selection_ring.visible = true

    # Auto-follow when not in observer mode
    if not _observer_active:
      camera.follow_target = node
  else:
    _selected_node = null
    _selection_ring.visible = false


func _on_ship_removed(id: String) -> void:
  # If we're POV-ing this ship, bail back to the normal camera.
  if camera.pov_target and camera.pov_target.get("ship_id") == id:
    camera.exit_pov()
  _detach_selection_if_matches(id, "ship_id")


func _on_facility_removed(id: String) -> void:
  _detach_selection_if_matches(id, "facility_id")


func _detach_selection_if_matches(id: String, prop: String) -> void:
  # Shared selection-tear-down: if the removed entity was what we had
  # selected, move the selection ring off its soon-to-be-freed parent
  # and reset state.
  if _selected_node and _selected_node.get(prop) == id:
    if _selection_ring and _selection_ring.get_parent() == _selected_node:
      _selected_node.remove_child(_selection_ring)
      add_child(_selection_ring)
    _clear_selection()


func _on_server_died(reason: String) -> void:
  # Dev mode (external server) — ServerManager shouldn't fire this, but
  # double-check so a dev-side restart never punts back to the menu.
  if ServerManager.is_using_existing_server():
    push_warning("[Main] server_died during dev mode, ignoring: %s" % reason)
    return
  GameState.show_toast(
    "Simulator stopped: %s" % reason, ThemePalette.DANGER
  )
  NetworkManager.disconnect_ws()
  get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _clear_selection() -> void:
  GameState.selected_entity_id = ""
  _details_panel.deselect()
  _selected_node = null
  _selection_ring.visible = false
  if not _observer_active:
    camera.follow_target = null


func _find_entity_node(id: String, type: String) -> Node3D:
  match type:
    "ship":
      return universe.get_ship_node(id)
    "facility":
      return universe.get_facility_node(id)
  return null


func _on_ship_list_selected(ship_id: String) -> void:
  _select_entity(ship_id, "ship", "")


func _on_contract_selected(contract_id: String) -> void:
  ## From the contracts panel — if the contract has a fulfiller_id,
  ## select that ship. Otherwise no-op; the contract data itself is
  ## visible in-row.
  var contract = GameState.contracts.get(contract_id)
  if contract is Dictionary:
    var fulfiller = contract.get("fulfiller_id")
    if fulfiller != null and str(fulfiller) != "":
      _select_entity(str(fulfiller), "ship", "")


func _on_focus_requested(agent_id: String) -> void:
  ## From the events ticker — click an event and we try to pick the
  ## right entity type from the id prefix.
  if agent_id.begins_with("ship-"):
    _select_entity(agent_id, "ship", "")
  elif agent_id.begins_with("facility-"):
    _select_entity(agent_id, "facility", "")
  elif agent_id.begins_with("contract-"):
    _on_contract_selected(agent_id)
  else:
    # Probably a location slug → jump camera there.
    _on_location_selected(agent_id)


func _on_step_requested(ticks: int) -> void:
  NetworkManager.post_sim_control("step", {"ticks": ticks})


func _on_location_selected(location: String) -> void:
  # Find the facility at this location and jump camera there
  for fac in GameState.facilities.values():
    if fac.get("location", "") == location:
      var pos = fac.get("position", {})
      if pos is Dictionary:
        var x: float = float(pos.get("x", 0.0))
        var y: float = float(pos.get("y", 0.0))
        var world := GameState.server_to_world(x, y)
        camera.follow_target = null
        camera.focus_on(world)
        return


func _handle_right_click(screen_pos: Vector2) -> void:
  var hit := _find_nearest_entity(screen_pos)
  if hit.id != "":
    _context_menu.show_for_entity(
      hit.id, hit.type, screen_pos
    )


func _on_context_action(
  action: String, entity_id: String, entity_type: String
) -> void:
  match action:
    "Inspect":
      _select_entity(entity_id, entity_type, "")
    "Follow":
      var node := _find_entity_node(entity_id, entity_type)
      if node:
        _select_entity(entity_id, entity_type, "")
        camera.follow_target = node
    "Focus":
      var node := _find_entity_node(entity_id, entity_type)
      if node:
        camera.focus_on(node.global_position)
    "Track Route":
      _select_entity(entity_id, entity_type, "")
    "View Market":
      _select_entity(entity_id, entity_type, "")
    "POV":
      var node := _find_entity_node(entity_id, entity_type)
      if node:
        # Observer mode doesn't mix with POV — bail out first.
        # set_observer_active fires the signal → handler flips
        # camera / selection back to clean state.
        if _observer_active:
          hud.set_observer_active(false)
        _select_entity(entity_id, entity_type, "")
        camera.enter_pov(node)
        var ship: Dictionary = GameState.ships.get(
          entity_id, {}
        )
        var ship_name: String = str(
          ship.get("name", entity_id)
        )
        GameState.show_toast(
          "POV: %s — Esc to exit" % ship_name,
          ThemePalette.PRIMARY
        )
    "Destroy":
      _god_destroy_entity(entity_id, entity_type)
    "Edit Supply":
      if entity_type == "facility":
        _facility_reserves_panel.open_for(entity_id)


# -------------------- God-mode handlers --------------------

func _on_destroy_toggled(active: bool) -> void:
  _destroy_mode = active
  if active:
    GameState.show_toast(
      "Destroy mode — click ships/facilities to delete (Esc to exit)",
      ThemePalette.DANGER
    )
  else:
    # Cursor / ring restore happens in _update_destroy_hover when
    # _destroy_mode flips false.
    Input.set_default_cursor_shape(Input.CURSOR_ARROW)
    if _destroy_hover:
      _destroy_hover.visible = false


func _exit_destroy_mode() -> void:
  if not _destroy_mode:
    return
  _destroy_mode = false
  Input.set_default_cursor_shape(Input.CURSOR_ARROW)
  if _destroy_hover:
    _destroy_hover.visible = false
  if _god_toolbar:
    _god_toolbar.set_destroy_pressed(false)


func _update_destroy_hover() -> void:
  # Runs every frame while destroy mode is active. Projects the
  # hovered entity's world position back to the screen and parks the
  # red ring there. Forbidden cursor only when over a valid target.
  var mouse_pos: Vector2 = get_viewport().get_mouse_position()
  var hovered := _find_nearest_entity(mouse_pos)
  var valid: bool = (
    hovered.id != ""
    and (hovered.type == "ship" or hovered.type == "facility")
  )
  if not valid:
    Input.set_default_cursor_shape(Input.CURSOR_ARROW)
    _destroy_hover.visible = false
    return
  # Pull live world position for the entity and re-project — entities
  # move between frames, so re-deriving here keeps the ring glued on.
  var world: Vector3 = _entity_world_pos(hovered.id, hovered.type)
  if is_nan(world.x):
    Input.set_default_cursor_shape(Input.CURSOR_ARROW)
    _destroy_hover.visible = false
    return
  Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
  _destroy_hover.show_at(camera.unproject_position(world))


func _entity_world_pos(id: String, type: String) -> Vector3:
  # Returns NaN-sentinel Vector3 when the entity / position is missing.
  var missing := Vector3(NAN, NAN, NAN)
  var pos: Variant
  if type == "ship":
    pos = GameState.ships.get(id, {}).get("position")
  else:
    pos = GameState.facilities.get(id, {}).get("position")
  if not (pos is Dictionary):
    return missing
  return GameState.server_to_world(
    float(pos.get("x", 0.0)), float(pos.get("y", 0.0))
  )


func _on_add_ship_pressed() -> void:
  _add_ship_panel.open()


func _on_add_facility_pressed() -> void:
  _add_facility_panel.open()


func _god_destroy_entity(id: String, type: String) -> void:
  ## Optimistic destroy: spawn explosion + local cleanup IMMEDIATELY on
  ## click, then fire the DELETE request asynchronously. Previously we
  ## waited for the server's 204, but the WebSocket
  ## `ship_decommissioned` event races ahead of the HTTP response and
  ## removes the entity node before our callback can read its position
  ## — which is why the old flow produced a silent pop with no VFX.
  ##
  ## Error handling: if the server rejects the DELETE, we toast the
  ## error. The entity stays erased client-side — it'll reappear on
  ## the next /api/report refresh (every 30 s) if the server thinks
  ## it's still alive.
  _spawn_destroy_explosion(id, type)
  if type == "ship":
    GameState.remove_ship_local(id)
    NetworkManager.admin_destroy_ship(
      id,
      func(code: int, body: String):
        if code != 204:
          _toast_admin_error("destroy ship", code, body)
    )
  elif type == "facility":
    GameState.remove_facility_local(id)
    NetworkManager.admin_destroy_facility(
      id,
      func(code: int, body: String):
        if code != 204:
          _toast_admin_error("destroy facility", code, body)
    )
  GameState.show_toast("destroyed %s" % id, ThemePalette.DANGER)


func _spawn_destroy_explosion(id: String, type: String) -> void:
  ## Place a ProceduralExplosion at the entity's current world position.
  ## Parented to Universe (not the entity) so the effect survives the
  ## entity's queue_free that follows a few lines later in the caller.
  var node: Node3D = _find_entity_node(id, type)
  if not node:
    return
  var entity_pos: Vector3 = node.global_position
  # Size hint: ships are rendered at SHIP_RENDER_SCALE × SIZE_SCALES tier
  # (≈ 0.0125–0.16 world units); facilities at ~0.012–0.035. Rough
  # defaults are close enough — the explosion clamps its own size range.
  var size_hint: float = 0.06 if type == "ship" else 0.04
  var boom := ProceduralExplosion.new()
  # Parent to the Universe root so the explosion sits in world space,
  # independent of the entity's local system/orbit frame.
  universe.add_child(boom)
  boom.global_position = entity_pos
  boom.play(size_hint)


func _on_create_ship_requested(data: Dictionary) -> void:
  NetworkManager.admin_create_ship(
    data,
    func(code: int, body: String):
      if code != 201:
        _toast_admin_error("create ship", code, body)
        return
      # Eagerly add to client state + spawn the 3D node rather than
      # waiting for the next /api/report refresh (30s). Server returns
      # {id, name, class, faction_id, location, credits} — partial,
      # but ship_states + positions broadcasts fill in the rest.
      var parsed = JSON.parse_string(body)
      if parsed is Dictionary:
        GameState.add_ship_local(parsed)
      GameState.show_toast(
        "ship created: %s" % str(data.get("name", "")),
        ThemePalette.SUCCESS
      )
  )


func _on_create_facility_requested(data: Dictionary) -> void:
  NetworkManager.admin_create_facility(
    data,
    func(code: int, body: String):
      if code != 201:
        _toast_admin_error("create facility", code, body)
        return
      var parsed = JSON.parse_string(body)
      if parsed is Dictionary:
        GameState.add_facility_local(parsed)
      GameState.show_toast(
        "facility created: %s" % str(data.get("name", "")),
        ThemePalette.SUCCESS
      )
  )


func _on_reserves_apply_requested(
  facility_location: String, deltas: Dictionary
) -> void:
  # Server takes one commodity per request, so we fire off N parallel
  # POSTs. The endpoint is loopback-only so concurrency is fine.
  if deltas.is_empty():
    GameState.show_toast("no changes", ThemePalette.TEXT_DIM)
    return
  for commodity in deltas:
    var delta: int = int(deltas[commodity])
    NetworkManager.admin_market_supply_delta(
      facility_location, str(commodity), delta,
      func(code: int, body: String):
        if code != 204:
          _toast_admin_error(
            "supply " + str(commodity), code, body
          )
    )
  GameState.show_toast(
    "%d supply change(s) applied" % deltas.size(),
    ThemePalette.INFO
  )


func _toast_admin_error(action: String, code: int, body: String) -> void:
  var msg := "%s failed (%d)" % [action, code]
  # Server returns {"error": "…"} on 4xx — surface it if present.
  var parsed = JSON.parse_string(body)
  if parsed is Dictionary and parsed.has("error"):
    msg = "%s: %s" % [action, parsed["error"]]
  push_warning("[God] " + msg)
  GameState.show_toast(msg, ThemePalette.DANGER)
