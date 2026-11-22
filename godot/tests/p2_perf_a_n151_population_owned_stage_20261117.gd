extends SceneTree

# N151 ownership regression: failed candidate writes must not touch the
# authoritative population rows, and staged data must match a full-copy oracle.
func _initialize() -> void:
    var original: Dictionary = {
        "populations": {
            "earth": {"count": 12, "wealth": 100, "flags": {"dirty": false}},
            "mars": {"count": 3, "wealth": 40, "flags": {"dirty": false}}
        },
        "ships": {"s1": {"cargo": {"ore": 7}}},
        "population_migration_last": {"tick": 1}
    }
    var before: Dictionary = original.duplicate(true)
    var oracle: Dictionary = original.duplicate(true)
    var stage: Dictionary = original.duplicate()
    stage["populations"] = original["populations"].duplicate(true)
    oracle["populations"]["earth"]["count"] = 11
    oracle["populations"]["mars"]["count"] = 4
    stage["populations"]["earth"]["count"] = 11
    stage["populations"]["mars"]["count"] = 4
    var event: Dictionary = {"tick": 200, "receipt_id": "migration"}
    oracle["population_migration_last"] = event.duplicate(true)
    stage["population_migration_last"] = event.duplicate(true)
    if stage != oracle or original != before:
        push_error("N151 owned stage differs from full-copy oracle or mutated World")
        quit(1)
        return
    stage["populations"]["earth"]["flags"]["dirty"] = true
    if original["populations"]["earth"]["flags"]["dirty"]:
        push_error("N151 failed-stage population nested alias leaked")
        quit(1)
        return
    # Negative regression: a shallow population domain is not a valid stage.
    var unsafe: Dictionary = original.duplicate()
    unsafe["populations"] = original["populations"].duplicate()
    unsafe["populations"]["earth"]["count"] = 9
    if original["populations"]["earth"]["count"] != 9:
        push_error("Negative shallow-alias regression did not expose unsafe write")
        quit(1)
        return
    quit(0)
