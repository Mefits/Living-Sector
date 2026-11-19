extends SceneTree
## Ownership regression only; no synthetic performance claim.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
    var parent: RefCounted = Ledger.new()
    assert(parent.import_accounts({"a": 100, "b": 0}))
    assert(parent.transfer("old", "a", "b", 10, 1, "test").get("ok", false))
    var saved: Dictionary = parent.snapshot()
    var parent_lifetime: WeakRef = weakref(parent)
    var child: RefCounted = parent.fork()
    assert(child.retains_owned_receipts(parent))
    parent = null
    assert(parent_lifetime.get_ref() == null)
    assert(child.snapshot() == saved)

    var latest: RefCounted = child
    child = null
    var ancestors: Array = []
    for index in range(32):
        ancestors.append(weakref(latest))
        latest = latest.fork()
    for ancestor in ancestors:
        assert(ancestor.get_ref() == null)
    assert(latest.snapshot() == saved)

    var staged: RefCounted = latest.fork()
    assert(staged.retains_owned_receipts(latest))
    assert(latest.restore(saved))
    # Same count is not the same provenance generation or immutable rows.
    assert(not staged.retains_owned_receipts(latest))
    assert(staged.snapshot() == saved)
    print("LATE_GROWTH_WEAK_PARENT_PASS released_ancestors retained_history strict_restore")
    quit(0)
