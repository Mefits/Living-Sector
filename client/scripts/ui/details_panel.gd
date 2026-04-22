extends PanelContainer

## Shows details about the currently selected entity (ship, facility, or body).
## Updates live each tick.

# Biome → chip color. Hints taken from the backend reference doc's
# "biome → renders as" table, mapped to readable accent colors.
const BIOME_COLORS := {
  "terrestrial": "#5ed99e",
  "ocean": "#3d7ccc",
  "desert": "#cc8852",
  "ice": "#c0e8ff",
  "asteroid": "#9a9a9a",
  "gas_giant": "#e8aa60",
  "molten": "#ff6644",
  "industrial": "#b09a80",
  "lifeless": "#808080",
}

var _selected_id: String = ""
var _selected_type: String = ""  # "ship", "facility", "body"

@onready var title_label: Label = $VBox/TitleLabel
@onready var type_label: Label = $VBox/TypeLabel
@onready var info_label: RichTextLabel = $VBox/InfoLabel
@onready var close_button: Button = $VBox/TopRow/CloseButton


func _ready() -> void:
  close_button.pressed.connect(deselect)
  GameState.tick_updated.connect(_on_tick)
  visible = false


func select_ship(id: String) -> void:
  _selected_id = id
  _selected_type = "ship"
  visible = true
  _refresh()


func select_facility(id: String) -> void:
  _selected_id = id
  _selected_type = "facility"
  visible = true
  _refresh()


func select_body(system_id: String, body_id: String) -> void:
  _selected_id = body_id
  _selected_type = "body"
  visible = true
  _refresh_body(system_id, body_id)


func deselect() -> void:
  _selected_id = ""
  _selected_type = ""
  visible = false


func is_selecting() -> bool:
  return visible


func _on_tick(_tick: int) -> void:
  if visible:
    _refresh()


## Append a "Recent activity" section to the details panel body showing
## the last ~8 events involving this entity. Pulled from
## `GameState.event_log` via `events_for_agent`. Works for ships,
## facilities, and body ids (ids are prefix-distinct so the ring filter
## does the right thing without knowing type).
func _append_activity_trail(lines: Array) -> void:
  if _selected_id == "":
    return
  var recent: Array = GameState.events_for_agent(_selected_id, 8)
  if recent.is_empty():
    return
  lines.append("")
  lines.append("[b]Recent activity[/b]")
  var now: int = GameState.tick
  for entry in recent:
    var ev: Dictionary = entry.get("event", {})
    var tick: int = int(entry.get("tick", 0))
    var age := now - tick
    var kind := str(ev.get("kind", "?"))
    var line := "  -%dt [color=%s]%s[/color]" % [
      age, ThemePalette.PRIMARY.to_html(), kind
    ]
    var payment = ev.get("payment")
    if payment != null:
      line += " pay=%d" % int(payment)
    var dest = ev.get("destination")
    if dest != null and str(dest) != "":
      line += " → %s" % str(dest)
    lines.append(line)


func _refresh() -> void:
  match _selected_type:
    "ship":
      _refresh_ship()
    "facility":
      _refresh_facility()


func _refresh_ship() -> void:
  var data: Dictionary = GameState.ships.get(_selected_id, {})
  if data.is_empty():
    deselect()
    return

  title_label.text = data.get("name", _selected_id)
  # Phase 18f: show size tier alongside the class label so operators
  # can tell a "size-5 tanker" apart from a "size-3 tanker" at a glance.
  var size_str: String = str(data.get("size", "")).capitalize()
  var tier_int: int = int(data.get("size_tier", 0))
  var class_label := str(data.get("class", "unknown")).capitalize()
  var class_line := class_label
  if size_str != "":
    class_line = "%s  |  %s (T%d)" % [class_label, size_str, tier_int]
  type_label.text = "%s  |  %s" % [
    class_line,
    GameState.faction_name(data.get("faction_id"))
  ]

  var lines: PackedStringArray = PackedStringArray()

  # Location & route
  var loc = data.get("location")
  var transit = data.get("transit")
  var docked_at = data.get("docked_at")

  if docked_at != null and str(docked_at) != "null":
    lines.append("Docked at: %s" % str(docked_at))
  elif loc != null and str(loc) != "null" and str(loc) != "":
    lines.append("At: %s" % str(loc))
  elif transit is Dictionary:
    var from_loc = transit.get("from", "?")
    var to_loc = transit.get("to", "?")
    var arrive: int = int(transit.get("arrival_tick", 0))
    var remaining: int = maxi(arrive - GameState.tick, 0)
    lines.append("[b]In transit[/b]")
    lines.append("  %s -> %s" % [from_loc, to_loc])
    if arrive > 0:
      lines.append("  ~%d ticks remaining" % remaining)
  else:
    lines.append("In space")

  var goal = data.get("current_goal")
  if goal != null and str(goal) != "null":
    lines.append("Goal: %s" % GameState.goal_label(goal))
  var bt = data.get("current_bt")
  if bt != null and str(bt) != "null":
    lines.append(
      "Action: %s" % str(bt).replace("_", " ").capitalize()
    )

  # Strike / warning indicators — make risk visible
  var broke: int = int(data.get("broke_strikes", 0))
  var hoard: int = int(data.get("hoard_strikes", 0))
  var idle: int = int(data.get("idle_ticks", 0))
  if broke > 0 or hoard > 0 or idle >= 10:
    var warns: PackedStringArray = PackedStringArray()
    if broke > 0:
      var broke_col: String = (
        "#ff6666" if broke >= 2 else "#ffaa55"
      )
      warns.append(
        "[color=%s]Broke %d/3[/color]" % [broke_col, broke]
      )
    if hoard > 0:
      var hoard_col: String = (
        "#ff6666" if hoard >= 2 else "#ffaa55"
      )
      warns.append(
        "[color=%s]Hoarding %d/3[/color]" % [hoard_col, hoard]
      )
    if idle >= 10:
      warns.append("[color=#cccc66]Idle %d ticks[/color]" % idle)
    lines.append("!  " + "  ".join(warns))

  # Active contract — lookup by id in GameState.contracts. Shows the
  # ship's current job (delivery, courier, passenger, crew mission, etc.)
  # so it's clear why it's going where it's going.
  var active_contract_id: String = str(data.get("active_contract_id", ""))
  if active_contract_id != "" and active_contract_id != "null":
    var contract = GameState.contracts.get(active_contract_id, null)
    if contract is Dictionary:
      var contract_type: String = str(
        contract.get("contract_type", "?")
      ).replace("_", " ").capitalize()
      var src: String = str(contract.get("source_location", ""))
      var dst: String = str(contract.get("destination_location", ""))
      var commodity: String = str(contract.get("commodity", ""))
      var qty: int = int(contract.get("quantity", 0))
      var pay: int = int(contract.get("payment", 0))
      var status: String = str(contract.get("status", ""))
      lines.append("")
      lines.append("[b]Job: %s[/b]" % contract_type)
      if src != "" and dst != "":
        lines.append("  %s → %s" % [src, dst])
      elif dst != "":
        lines.append("  → %s" % dst)
      if commodity != "" and qty > 0:
        lines.append("  %d × %s" % [qty, commodity])
      var footer: PackedStringArray = PackedStringArray()
      if pay > 0:
        footer.append("%d cr" % pay)
      if status != "":
        footer.append(status)
      if footer.size() > 0:
        lines.append("  " + " · ".join(footer))
      # Crew missions get extra display because they carry skill/duration.
      if str(contract.get("contract_type", "")) == "crew_mission":
        var display_name: String = str(
          contract.get(
            "display_name",
            str(contract.get("mission_category", "")).replace("_", " ").capitalize()
          )
        )
        var req_skill: String = str(contract.get("required_skill", ""))
        if display_name != "":
          lines.append("  %s" % display_name)
        if req_skill != "":
          lines.append("  skill: %s" % req_skill)

  # Cargo
  var cargo = data.get("cargo", {})
  var cap = data.get("cargo_capacity", 0)
  if cargo is Dictionary and cargo.size() > 0:
    var total := 0
    for qty in cargo.values():
      total += int(qty)
    lines.append("")
    lines.append("[b]Cargo[/b] (%d/%d)" % [total, cap])
    for commodity in cargo:
      var qty: int = int(cargo[commodity])
      if qty > 0:
        lines.append("  %s: %d" % [commodity, qty])

  # Fuel & credits
  lines.append("")
  lines.append(
    "Fuel: %.0f/%.0f" % [
      float(data.get("fuel", 0)),
      float(data.get("fuel_capacity", 0))
    ]
  )
  # Passengers only shown if the ship's rigged to carry them.
  var pax_cap: int = int(data.get("passenger_capacity", 0))
  if pax_cap > 0:
    lines.append(
      "Passengers: %d/%d" % [
        int(data.get("passengers", 0)), pax_cap
      ]
    )
  lines.append("Credits: %d" % int(data.get("credits", 0)))

  # Crew
  var crew = data.get("crew")
  if crew is Dictionary:
    lines.append("")
    lines.append("[b]Crew[/b] (size %d)" % int(crew.get("size", 0)))
    lines.append(
      "  Morale: %d  Health: %d" % [
        int(crew.get("morale", 0)),
        int(crew.get("health", 0))
      ]
    )
    lines.append(
      "  Hunger: %d  Fatigue: %d" % [
        int(crew.get("hunger", 0)),
        int(crew.get("fatigue", 0))
      ]
    )
    lines.append(
      "  Task: %s" % str(crew.get("current_task", "—"))
    )
    # Crew skills (grow on crew_mission completion, capped at 100)
    var skills = crew.get("skills")
    if skills is Dictionary and skills.size() > 0:
      var skill_keys: Array = skills.keys()
      skill_keys.sort()
      var parts: PackedStringArray = PackedStringArray()
      for k in skill_keys:
        parts.append("%s %d" % [str(k), int(skills[k])])
      lines.append("  Skills: " + " · ".join(parts))

  # Progression (Phase 18d) — ship-level XP + banked retrofit points.
  # Retrofit points drive autonomous refits: when a ship has >=1 point
  # and the credit reserve is clear, its planner routes to a stocked
  # shipyard and spends one to install a tier-up module.
  var prog = data.get("progression")
  if prog is Dictionary:
    lines.append("")
    lines.append("[b]Progression[/b]")
    var lvl: int = int(prog.get("level", 1))
    var xp: int = int(prog.get("xp", 0))
    var nxt: int = int(prog.get("next_level_threshold", 0))
    var rp: int = int(prog.get("retrofit_points", 0))
    var pct: int = 0
    if nxt > 0:
      pct = int(clampf(float(xp) / float(nxt), 0.0, 1.0) * 100.0)
    lines.append("  Level %d  (%d / %d XP  %d%%)" % [lvl, xp, nxt, pct])
    if rp > 0:
      lines.append(
        "  [color=#7fe7c9]Retrofit points: %d[/color]  [i](ready to install)[/i]" % rp
      )
    else:
      lines.append("  Retrofit points: 0")

  # Subsystems (Phase 18a) — fitted modules per slot + derived rollup
  var fitting = data.get("fitting")
  if fitting is Dictionary:
    lines.append("")
    lines.append("[b]Subsystems[/b]")
    var modules = fitting.get("modules", {})
    if modules is Dictionary:
      var slot_order: Array = ["engine", "cargo_bay", "sensors", "reactor", "comms"]
      for slot_name in slot_order:
        var slug = modules.get(slot_name)
        var label = str(slot_name).capitalize().replace("_", " ")
        if slug == null:
          lines.append("  %s: —" % label)
        else:
          lines.append("  %s: %s" % [label, str(slug)])
    var stats = fitting.get("stats")
    if stats is Dictionary:
      var speed_pct = (float(stats.get("speed_mult", 1.0)) - 1.0) * 100.0
      var cargo_pct = (float(stats.get("cargo_capacity_mult", 1.0)) - 1.0) * 100.0
      var fuel_pct = (1.0 - float(stats.get("fuel_efficiency_mult", 1.0))) * 100.0
      lines.append(
        "  Speed %+.0f%%  Cargo %+.0f%%  Fuel %+.0f%%" % [speed_pct, cargo_pct, fuel_pct]
      )
      var p_use: int = int(stats.get("power_use", 0))
      var p_cap: int = int(stats.get("power_cap", 0))
      var power_tag := " OK" if p_use <= p_cap else " OVER"
      lines.append("  Power: %d / %d%s" % [p_use, p_cap, power_tag])

  _append_activity_trail(lines)
  info_label.text = "\n".join(lines)


func _refresh_facility() -> void:
  var data: Dictionary = GameState.facilities.get(_selected_id, {})
  if data.is_empty():
    deselect()
    return

  title_label.text = data.get("name", _selected_id)
  type_label.text = "%s  |  %s" % [
    str(data.get("type", "unknown")).capitalize(),
    GameState.faction_name(data.get("faction_id"))
  ]

  var lines: PackedStringArray = PackedStringArray()

  lines.append(
    "Condition: %.0f%%" % (float(data.get("condition", 1.0)) * 100)
  )
  lines.append("Credits: %d" % int(data.get("credits", 0)))

  # Services
  var services = data.get("services", [])
  if services is Array and services.size() > 0:
    var svc_strs: PackedStringArray = PackedStringArray()
    for s in services:
      svc_strs.append(str(s))
    lines.append("")
    lines.append("[b]Services[/b]: %s" % ", ".join(svc_strs))

  # Docking
  var docked = data.get("docked_ships", [])
  var dock_cap: int = int(data.get("docking_capacity", 0))
  if docked is Array:
    lines.append(
      "Docked: %d/%d ships" % [docked.size(), dock_cap]
    )

  # Reserves
  var reserves = data.get("reserves", {})
  if reserves is Dictionary and reserves.size() > 0:
    lines.append("")
    lines.append("[b]Reserves[/b]")
    for commodity in reserves:
      var qty: int = int(reserves[commodity])
      if qty > 0:
        lines.append("  %s: %d" % [commodity, qty])

  # Facility subsystems (Phase 18e) — Production + Automation slots
  # + derived rollup. Absent on gates; present (neutral by default)
  # on every other facility.
  var fac_fitting = data.get("fitting")
  if fac_fitting is Dictionary:
    lines.append("")
    lines.append("[b]Subsystems[/b]")
    var fac_modules = fac_fitting.get("modules", {})
    if fac_modules is Dictionary:
      for slot_name in ["production", "automation"]:
        var slug3 = fac_modules.get(slot_name)
        var label3 = str(slot_name).capitalize()
        if slug3 == null:
          lines.append("  %s: —" % label3)
        else:
          lines.append("  %s: %s" % [label3, str(slug3)])
    var fac_stats = fac_fitting.get("stats")
    if fac_stats is Dictionary:
      var out_pct = (float(fac_stats.get("recipe_output_mult", 1.0)) - 1.0) * 100.0
      var batch_bonus: int = int(fac_stats.get("max_batches_bonus", 0))
      lines.append(
        "  Output %+.0f%%  Batches +%d" % [out_pct, batch_bonus]
      )

  # Shipyard module stock (Phase 18c). Absent on non-shipyards.
  # Sorted so the slot ordering matches the ship details panel.
  var module_stock = data.get("module_stock")
  if module_stock is Dictionary and module_stock.size() > 0:
    lines.append("")
    lines.append("[b]Module Stock[/b]  [i](installable subsystems)[/i]")
    var keys: Array = module_stock.keys()
    keys.sort()
    for slug in keys:
      var qty2: int = int(module_stock[slug])
      if qty2 > 0:
        lines.append("  %s × %d" % [str(slug), qty2])
  elif str(data.get("type", "")) == "shipyard":
    # Shipyard exists but stock empty — useful to see so players
    # know production is lagging.
    lines.append("")
    lines.append(
      "[b]Module Stock[/b]  [i](empty — awaiting production)[/i]"
    )

  # Market — only if this facility has one (matched by location)
  var fac_loc: String = str(data.get("location", ""))
  var market: Dictionary = {}
  for m in GameState.markets.values():
    if str(m.get("facility_id", "")) == fac_loc:
      market = m
      break
  if market.size() > 0:
    var prices = market.get("prices", {})
    var supply = market.get("supply", {})
    var demand = market.get("demand", {})
    var shortage = market.get("shortage_ticks", {})
    if prices is Dictionary and prices.size() > 0:
      lines.append("")
      lines.append("[b]Market[/b]")
      var sorted_cmd: Array = prices.keys()
      sorted_cmd.sort()
      for commodity in sorted_cmd:
        var p: float = float(prices.get(commodity, 0))
        if p <= 0 or p >= 500:
          continue  # skip unavailable
        var s: int = (
          int(supply.get(commodity, 0))
          if supply is Dictionary else 0
        )
        var d: int = (
          int(demand.get(commodity, 0))
          if demand is Dictionary else 0
        )
        var sh: int = (
          int(shortage.get(commodity, 0))
          if shortage is Dictionary else 0
        )
        var line: String = "  %s: %d  (sup %d / dem %d)" % [
          commodity, int(p), s, d
        ]
        if sh > 0:
          var col: String = (
            "#ff6666" if sh >= 30 else "#ffaa55"
          )
          line += (
            "  [color=%s]SHORTAGE %dt[/color]" % [col, sh]
          )
        lines.append(line)

  # Crew
  var crew = data.get("crew")
  if crew is Dictionary:
    lines.append("")
    lines.append("[b]Crew[/b] (size %d)" % int(crew.get("size", 0)))
    lines.append(
      "  Morale: %d  Health: %d" % [
        int(crew.get("morale", 0)),
        int(crew.get("health", 0))
      ]
    )

  _append_activity_trail(lines)
  info_label.text = "\n".join(lines)


func _refresh_body(system_id: String, body_id: String) -> void:
  var sys: Dictionary = GameState.systems.get(system_id, {})
  for body in sys.get("bodies", []):
    if body.get("id") == body_id:
      title_label.text = body.get("name", body_id)
      type_label.text = str(
        body.get("type", "body")
      ).capitalize()

      var lines: PackedStringArray = PackedStringArray()

      # Biome chip — colored square + name. Color hints come from
      # the server's biome → render table in the backend reference
      # doc; unknown biomes fall back to dim text.
      var biome = body.get("biome")
      if biome != null and str(biome) != "null":
        var biome_key: String = str(biome)
        var chip_col: String = BIOME_COLORS.get(
          biome_key, "#8aaacc"
        )
        var pretty: String = biome_key.replace(
          "_", " "
        ).capitalize()
        lines.append(
          "Biome: [color=%s]\u25a0[/color] %s" % [
            chip_col, pretty
          ]
        )

      # Static resource richness. Keys sorted for stable order.
      var resources = body.get("resources")
      if resources is Dictionary and resources.size() > 0:
        var keys: Array = resources.keys()
        keys.sort()
        var parts: PackedStringArray = PackedStringArray()
        for k in keys:
          var v: float = float(resources.get(k, 0))
          if v <= 0.0:
            continue
          parts.append("%s %.0f%%" % [str(k), v * 100.0])
        if parts.size() > 0:
          lines.append("Resources: " + ", ".join(parts))

      lines.append("")
      lines.append(
        "Orbit radius: %.2f" % float(
          body.get("orbit_radius", 0)
        )
      )
      lines.append(
        "Orbit period: %d ticks" % int(
          body.get("orbit_period", 0)
        )
      )
      _append_activity_trail(lines)
      info_label.text = "\n".join(lines)
      return
