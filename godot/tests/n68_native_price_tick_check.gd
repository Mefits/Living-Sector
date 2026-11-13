extends SceneTree
## CODE_UNVERIFIED — --headless --path godot --script res://tests/n68_native_price_tick_check.gd
const Book = preload("res://scripts/sim/economy/native_price_tick_book.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var book = Book.new()
	_check(book.import_markets({"m": {"ore": 100.0}}), "import")
	var stocks := {"m": {"ore": 0.0}}
	var demand := {"m": {"ore": 10.0}}
	var e := {"m": 0.02}
	var shortage := {"m": {"ore": 30}}
	_check(book.tick(1, stocks, demand, e, shortage).ok, "one price tick")
	var price := book.prices("m").ore
	_check(price > 100.0, "native shortage price increases")
	_check(not book.tick(1, stocks, demand, e, shortage).ok, "replay refused")
	_check(book.prices("m").ore == price, "replay immutable")
	var saved := book.snapshot()
	var restored = Book.new()
	_check(restored.restore(saved), "restore")
	_check(not restored.tick(1, stocks, demand, e, shortage).ok, "replay refused after restore")
	_check(not restored.tick(2, {"m": {"ore": -1.0}}, demand, e, shortage).ok, "invalid stock refused")
	_check(restored.prices("m").ore == price, "invalid atomic")
	_check(not restored.restore({"version": 1, "markets": {"m": {"ore": -1.0}}, "last_tick": {"m": 3}}), "corrupt restore")
	_check(restored.prices("m").ore == price, "restore atomic")
	if failures.is_empty():
		print("N68_NATIVE_PRICE_TICK_PASS")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		quit(1)
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
