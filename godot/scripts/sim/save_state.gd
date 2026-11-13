extends RefCounted
## P1 checkpoint persistence with SHA-256 integrity envelope and atomic recovery.
## The digest protects against accidental corruption, NOT malicious save editing.
## Legacy schema-v1 bare checkpoints remain readable (without a digest).
## CODE_UNVERIFIED until the Godot headless regression is executed.

const DEFAULT_PATH: String = "user://saves/galaxy-067-p1.json"
const ENVELOPE_FORMAT: String = "living-sector-checkpoint-envelope"
const ENVELOPE_VERSION: int = 1
const MAX_SAVE_BYTES: int = 16 * 1024 * 1024

static func _canonical(value: Variant) -> String:
    if value is Dictionary:
        var keys: Array = value.keys()
        keys.sort()
        var parts: PackedStringArray = PackedStringArray()
        for key in keys:
            parts.append(JSON.stringify(str(key)) + ":" + _canonical(value[key]))
        return "{" + ",".join(parts) + "}"
    if value is Array:
        var parts: PackedStringArray = PackedStringArray()
        for item in value:
            parts.append(_canonical(item))
        return "[" + ",".join(parts) + "]"
    return JSON.stringify(value)

static func _wrap(snapshot: Dictionary) -> Dictionary:
    # Hash the JSON-normalized payload, not GDScript integer/float variants:
    # JSON parsing may turn 7 into 7.0, and the digest must survive reload.
    var normalized: Variant = JSON.parse_string(JSON.stringify(snapshot))
    return {
        "envelope_format": ENVELOPE_FORMAT,
        "envelope_version": ENVELOPE_VERSION,
        "payload_sha256": _canonical(normalized).sha256_text(),
        "payload": normalized
    }

static func _unwrap(raw: Variant) -> Dictionary:
    if not (raw is Dictionary):
        return {}
    if raw.has("envelope_format") or raw.has("payload_sha256") or raw.has("payload"):
        if raw.get("envelope_format", "") != ENVELOPE_FORMAT:
            return {}
        if raw.get("envelope_version", 0) != ENVELOPE_VERSION:
            return {}
        var payload: Variant = raw.get("payload", null)
        var digest: Variant = raw.get("payload_sha256", null)
        if not (payload is Dictionary) or not (digest is String):
            return {}
        if digest.length() != 64 or _canonical(payload).sha256_text() != digest:
            return {}
        return payload
    # Old P1 saves: validation still occurs inside TickRunner.restore_checkpoint.
    if raw.get("format", "") == "living-sector-godot":
        return raw
    return {}

static func _read_checkpoint(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var size: int = file.get_length()
    if size <= 0 or size > MAX_SAVE_BYTES:
        file.close()
        return {}
    var raw_text: String = file.get_as_text()
    file.close()
    var parser := JSON.new()
    if parser.parse(raw_text) != OK:
        return {}
    return _unwrap(parser.data)

static func save_runner(runner: RefCounted, save_path: String = DEFAULT_PATH) -> Error:
    if not runner.is_started():
        return ERR_INVALID_DATA
    var snapshot: Dictionary = runner.checkpoint()
    if snapshot.is_empty():
        return ERR_INVALID_DATA
    var absolute_path: String = ProjectSettings.globalize_path(save_path)
    var folder: String = absolute_path.get_base_dir()
    var mkdir_result: Error = DirAccess.make_dir_recursive_absolute(folder)
    if mkdir_result != OK:
        return mkdir_result

    var tmp: String = absolute_path + ".pending"
    var backup: String = absolute_path + ".bak"
    var encoded: String = JSON.stringify(_wrap(snapshot), "\t") + "\n"
    if encoded.to_utf8_buffer().size() > MAX_SAVE_BYTES:
        return ERR_OUT_OF_MEMORY
    var file := FileAccess.open(tmp, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(encoded)
    file.flush()
    var write_error: Error = file.get_error()
    file.close()
    if write_error != OK:
        DirAccess.remove_absolute(tmp)
        return write_error
    if _read_checkpoint(tmp).is_empty():
        DirAccess.remove_absolute(tmp)
        return ERR_FILE_CORRUPT

    var had_primary: bool = FileAccess.file_exists(absolute_path)
    var primary_is_valid: bool = had_primary and not _read_checkpoint(absolute_path).is_empty()
    # Never overwrite a known-good backup with a damaged primary.
    if had_primary and primary_is_valid:
        if FileAccess.file_exists(backup):
            var remove_result: Error = DirAccess.remove_absolute(backup)
            if remove_result != OK:
                DirAccess.remove_absolute(tmp)
                return remove_result
        var backup_result: Error = DirAccess.rename_absolute(absolute_path, backup)
        if backup_result != OK:
            DirAccess.remove_absolute(tmp)
            return backup_result
    elif had_primary:
        # Invalid primary is not a usable recovery point.
        var remove_primary: Error = DirAccess.remove_absolute(absolute_path)
        if remove_primary != OK:
            DirAccess.remove_absolute(tmp)
            return remove_primary

    var promote_result: Error = DirAccess.rename_absolute(tmp, absolute_path)
    if promote_result != OK:
        if had_primary and primary_is_valid:
            DirAccess.rename_absolute(backup, absolute_path)
        return promote_result
    return OK

static func load_runner(runner: RefCounted, seed: Dictionary,
        save_path: String = DEFAULT_PATH) -> Dictionary:
    if not runner.is_started():
        return {"ok": false, "error": "Simulation is not initialized"}
    # restore_checkpoint may reject an invalid payload after touching some state.
    # Keep the authoritative live snapshot and roll back before trying .bak.
    var baseline: Dictionary = runner.checkpoint()
    if baseline.is_empty():
        return {"ok": false, "error": "Cannot protect live state before restore"}
    var absolute_path: String = ProjectSettings.globalize_path(save_path)
    # The .pending file may be the only intact checkpoint if a process died
    # between writing it and promoting it to the primary path. Never prefer
    # an uncommitted pending save over a healthy primary or known-good backup.
    for candidate in [absolute_path, absolute_path + ".bak", absolute_path + ".pending"]:
        var parsed: Dictionary = _read_checkpoint(candidate)
        if parsed.is_empty():
            continue
        if runner.restore_checkpoint(parsed, seed):
            return {
                "ok": true,
                "source": candidate,
                "tick": runner.tick_count,
                "recovered_pending": candidate == absolute_path + ".pending"
            }
        if not runner.restore_checkpoint(baseline, seed):
            return {
                "ok": false,
                "error": "Checkpoint rejected and live-state rollback failed; stop simulation"
            }
    return {
        "ok": false,
        "error": "Save is missing, incompatible, incomplete or corrupted; live world restored"
    }
