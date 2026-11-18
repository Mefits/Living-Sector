extends SceneTree
## Verify actual local inventories, not display fixture numbers.
const Starter = preload("res://scripts/sol_start_scenario.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Runtime = preload("res://scripts/sol_construction_runtime.gd")
const StockPanel = preload("res://scripts/view/colony_stock_panel.gd")

func _make_runtime() -> Variant:
 var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
  "res://data/sol.json"))
 var world: Dictionary = Starter.apply(parsed)
 var runtime = Runtime.new()
 runtime.planets = Model.planet_defaults(world)
 runtime.setup(world, Model.building_defaults())
 return runtime

func _amount(panel: Variant, resource: String) -> String:
 var label: Variant = panel.amount_labels.get(resource, null)
 return str(label.text) if label is Label else ""

func _initialize() -> void:
 var ok := true
 var runtime = _make_runtime()
 var panel = StockPanel.new()
 root.add_child(panel)
 # Earth starts with its own real inventory.
 panel.show_inventory("Земля", runtime.colony_inventory("earth"))
 ok = ok and panel.visible and panel.heading.text == "Склад колонии · Земля"
 ok = ok and _amount(panel, "metals") == "1000"
 ok = ok and (panel.amount_labels["metals"] as Label).horizontal_alignment == (
  HORIZONTAL_ALIGNMENT_RIGHT)
 # The uncolonized Moon has no panel, not a fake empty warehouse.
 panel.show_inventory("Луна", runtime.colony_inventory("luna"))
 ok = ok and not panel.visible
 # A real landing creates Luna's own store of two metals.
 ok = ok and runtime.expedition.depart(0.0)
 var landing: float = Calendar.days_to_native(12.0)
 runtime.advance_to(landing)
 panel.show_inventory("Луна", runtime.colony_inventory("luna"))
 ok = ok and panel.visible and panel.heading.text == "Склад колонии · Луна"
 ok = ok and _amount(panel, "metals") == "2"
 # Ordering a mine debits the *lunar* warehouse immediately.
 ok = ok and bool(runtime.order("luna", "mining_rig").get("ok", false))
 panel.show_inventory("Луна", runtime.colony_inventory("luna"))
 ok = ok and _amount(panel, "metals") == "1"
 # Switching back never leaks Lunar inventory into Earth.
 panel.show_inventory("Земля", runtime.colony_inventory("earth"))
 ok = ok and panel.visible and _amount(panel, "metals") == "1000"
 # Restore preserves that same local store and UI projection.
 var saved: Variant = JSON.parse_string(JSON.stringify(runtime.snapshot()))
 var resumed = _make_runtime()
 ok = ok and resumed.restore(saved)
 panel.show_inventory("Луна", resumed.colony_inventory("luna"))
 ok = ok and panel.visible and _amount(panel, "metals") == "1"
 panel.queue_free()
 if ok:
  print("SOL_COLONY_STOCK_PANEL_PASS")
  quit(0)
 else:
  push_error("SOL_COLONY_STOCK_PANEL_FAIL")
  quit(1)
