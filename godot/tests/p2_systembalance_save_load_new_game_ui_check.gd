extends SceneTree
## Fast GUI menu regression, no N158 paid ticks, save-file mutation or CI.
## Running this test requires a local Godot engine. It does NOT perform a
## real checkpoint round trip; the existing N38 tests cover that separately.
const Main = preload("res://scripts/main.gd")
const UI = preload("res://scripts/view/strategy_ui.gd")

class FakeGame extends Control:
    var last_action: String = ""
    func _new_game() -> void:
        last_action = "new_game"
    func _save_game() -> void:
        last_action = "save"
    func _load_game() -> void:
        last_action = "load"

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var game: Control = Main.new()
    assert(game.has_method("_new_game"))
    assert(game.has_method("_restart_new_game"))
    assert(game.has_method("_checkpoint_exists"))
    assert(not bool(game.call("_checkpoint_exists",
        "user://tests/p2-save-menu-never-exists-" + str(
            Time.get_ticks_usec()) + ".json")))
    game.free()

    var root := Control.new()
    root.size = Vector2(1366, 768)
    get_root().add_child(root)
    var ui: Control = UI.new()
    root.add_child(ui)
    ui.size = root.size

    var menu: PopupMenu = ui.get("_tools_menu")
    assert(menu != null)
    assert(menu.item_count >= 8)
    assert(menu.get_item_text(5) == "Новая игра")
    assert(menu.get_item_text(6) == "Сохранить")
    assert(menu.get_item_text(7) == "Загрузить")

    var fake := FakeGame.new()
    root.add_child(fake)
    ui.attach(fake)
    ui.call("_on_tools_selected", 5)
    assert(fake.last_action == "new_game")
    ui.call("_on_tools_selected", 6)
    assert(fake.last_action == "save")
    ui.call("_on_tools_selected", 7)
    assert(fake.last_action == "load")

    root.queue_free()
    print("P2_SYSTEMBALANCE_SAVE_LOAD_MENU_PASS")
    quit(0)
