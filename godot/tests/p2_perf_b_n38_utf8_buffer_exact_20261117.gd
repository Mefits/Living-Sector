extends SceneTree
## N38 UTF-8 byte path: Unicode, exact on-disk bytes, size and SHA rejection.
const SaveState = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var snapshot: Dictionary = {
        "format": "living-sector-godot",
        "tick": 7,
        "wallets": {"alpha": 123456789},
        "label": "Сектор Ω 🚀",
        "native_production": {"price": 1.25}
    }
    var encoded: String = SaveState._encode_checkpoint_text(snapshot)
    var bytes: PackedByteArray = encoded.to_utf8_buffer()
    assert(bytes.size() == SaveState.encoded_checkpoint_bytes(snapshot))
    assert(bytes.size() > encoded.length())
    assert(bytes.size() <= SaveState.MAX_SAVE_BYTES)
    assert(encoded.ends_with("\n"))
    var path: String = "user://p2_perf_b_n38_utf8_buffer_exact_20261117.tmp"
    var writer := FileAccess.open(path, FileAccess.WRITE)
    assert(writer != null)
    writer.store_buffer(bytes)
    writer.close()
    var reader := FileAccess.open(path, FileAccess.READ)
    assert(reader != null)
    var disk: PackedByteArray = reader.get_buffer(reader.get_length())
    reader.close()
    assert(disk == bytes)
    var parsed: Variant = JSON.parse_string(disk.get_string_from_utf8())
    var decoded: Dictionary = SaveState._unwrap(parsed)
    assert(not decoded.is_empty())
    assert(decoded["label"] == snapshot["label"])
    assert(decoded["wallets"] == snapshot["wallets"])
    # A changed SHA-covered payload must never be accepted.
    parsed["payload"]["label"] = "tampered"
    assert(SaveState._unwrap(parsed).is_empty())
    assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
    print("PASS p2_perf_b_n38_utf8_buffer_exact_20261117")
    quit(0)
