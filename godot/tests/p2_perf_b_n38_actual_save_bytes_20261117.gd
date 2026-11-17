extends SceneTree
## N38 diagnostic must not serialize an invalid runner or change its last
## measured byte count. Full successful-save parity requires real N158 CI.
const SaveState = preload("res://scripts/sim/save_state.gd")

class UnstartedRunner:
    extends RefCounted
    func is_started() -> bool:
        return false
    func checkpoint() -> Dictionary:
        assert(false, "An unstarted runner must never be snapshotted")
        return {}

func _initialize() -> void:
    var previous: int = SaveState.last_save_encoded_bytes()
    assert(previous >= -1)
    var snapshot: Dictionary = {"text": "тест 🚀", "nested": {"amount": 3}}
    var expected: int = SaveState._encode_checkpoint_text(snapshot).to_utf8_buffer().size()
    assert(SaveState.encoded_checkpoint_bytes(snapshot) == expected)
    assert(SaveState.encoded_checkpoint_budget(snapshot)["encoded_bytes"] == expected)
    assert(SaveState.save_runner(UnstartedRunner.new(),
        "user://p2-perf-b-never-write.json") == ERR_INVALID_DATA)
    assert(SaveState.last_save_encoded_bytes() == previous)
    print("P2_PERF_B_N38_ACTUAL_SAVE_BYTES_PASS")
    quit()
