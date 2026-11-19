extends RefCounted
## Targeted N38 size diagnostics; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN.
## Invoke run() from a Godot headless harness. Never touches a real save.
const SaveState = preload("res://scripts/sim/save_state.gd")

static func run() -> Dictionary:
    var tiny: Dictionary = {"format": "living-sector-godot", "note": "é"}
    var wrapped_text: String = SaveState._encode_checkpoint_text(tiny)
    var budget: Dictionary = SaveState.encoded_checkpoint_budget(tiny)
    if not wrapped_text.ends_with("\n"):
        return {"ok": false, "reason": "missing_terminal_newline"}
    if not wrapped_text.contains("payload_sha256"):
        return {"ok": false, "reason": "missing_envelope"}
    if int(budget.get("encoded_bytes", -1)) != wrapped_text.to_utf8_buffer().size():
        return {"ok": false, "reason": "encoded_byte_mismatch"}
    if int(budget.get("max_bytes", -1)) != SaveState.MAX_SAVE_BYTES:
        return {"ok": false, "reason": "limit_changed"}
    if not bool(budget.get("within_limit", false)):
        return {"ok": false, "reason": "tiny_save_rejected"}
    var oversized: Dictionary = {"format": "living-sector-godot",
        "padding": "x".repeat(SaveState.MAX_SAVE_BYTES)}
    var large_budget: Dictionary = SaveState.encoded_checkpoint_budget(oversized)
    if bool(large_budget.get("within_limit", true)):
        return {"ok": false, "reason": "oversized_save_accepted"}
    if int(large_budget.get("remaining_bytes", -1)) != 0:
        return {"ok": false, "reason": "oversized_remaining_nonzero"}
    # Diagnostics must not mutate caller-owned checkpoint content.
    if tiny.get("note") != "é" or oversized["padding"].length() != SaveState.MAX_SAVE_BYTES:
        return {"ok": false, "reason": "input_mutated"}
    return {"ok": true, "small_bytes": budget["encoded_bytes"],
        "large_bytes": large_budget["encoded_bytes"]}
