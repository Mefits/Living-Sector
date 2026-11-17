extends SceneTree

const SaveState = preload("res://scripts/sim/save_state.gd")

class RejectedRunner:
    extends RefCounted
    func is_started() -> bool:
        return false

func _initialize() -> void:
    var prior_bytes: int = SaveState.last_save_encoded_bytes()
    var prior_usec: int = SaveState.last_save_encode_usec()
    # Diagnostics must be observational: reading them cannot re-encode a save.
    for i in range(4):
        assert(SaveState.last_save_encoded_bytes() == prior_bytes)
        assert(SaveState.last_save_encode_usec() == prior_usec)
    # Negative regression: rejected preflight must not record a phantom encode
    # or touch .pending/.bak; no initialized native World is required.
    var error: Error = SaveState.save_runner(RejectedRunner.new(),
        "user://p2_perf_b_rejected_encode_probe.json")
    assert(error == ERR_INVALID_DATA)
    assert(SaveState.last_save_encoded_bytes() == prior_bytes)
    assert(SaveState.last_save_encode_usec() == prior_usec)
    # UTF-8 bytes, not codepoints: the budget helper must remain exact and
    # must not mutate the last *actual save* measurement.
    var snapshot: Dictionary = {"probe": "данные 🚀", "value": 1.25}
    var budget: Dictionary = SaveState.encoded_checkpoint_budget(snapshot)
    assert(int(budget["encoded_bytes"]) ==
        SaveState._encode_checkpoint_text(snapshot).to_utf8_buffer().size())
    assert(SaveState.last_save_encoded_bytes() == prior_bytes)
    assert(SaveState.last_save_encode_usec() == prior_usec)
    print("P2 PERF B N38 encode timing negative regression PASS")
    quit()
