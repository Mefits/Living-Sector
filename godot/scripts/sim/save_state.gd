extends RefCounted
## P1 checkpoint persistence with SHA-256 integrity envelope and atomic recovery.
## The digest protects against accidental corruption, NOT malicious save editing.
## Legacy schema-v1 bare checkpoints remain readable (without a digest).
## CODE_UNVERIFIED until the Godot headless regression is executed.

const DEFAULT_PATH: String = "user://saves/galaxy-067-p1.json"
const ENVELOPE_FORMAT: String = "living-sector-checkpoint-envelope"
const ENVELOPE_VERSION: int = 1
const MAX_SAVE_BYTES: int = 16 * 1024 * 1024
const NativeFrameGuard = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const NativeCoherence = preload("res://scripts/sim/phase2/unified_native_checkpoint_coherence.gd")
const NativeTimeline = preload("res://scripts/sim/phase2/unified_native_timeline_integrity.gd")
const SourceClock = preload("res://scripts/sim/clock.gd")
const SourceCalendar = preload("res://scripts/sim/calendar.gd")
const SourceCadence = preload("res://scripts/sim/cadence.gd")
const SourceEvents = preload("res://scripts/sim/event_queue.gd")
const SourceTickRunner = preload("res://scripts/sim/tick_runner.gd")

## Native N39 stores exact f64 amounts and market history. Godot's JSON
## formatter is not always a bit-exact roundtrip even with full_precision.
## Store native f64 as lossless Variant bytes encoded in an ordinary JSON
## string. The existing SHA-256 envelope authenticates these strings.
## No gameplay field is rounded, coerced, removed or reset. P1 and old
## plain numeric N38 JSON payloads remain readable.
const NATIVE_F64_TAG: String = "__ls_native_f64_exact_b64_v1__"
const NATIVE_DICT_TAG: String = "__ls_native_exact_dictionary_b64_v1__"
const MAX_NATIVE_DEPTH: int = 96

static func _encode_native_f64(value: Variant, depth: int = 0) -> Variant:
    if depth > MAX_NATIVE_DEPTH:
        return null
    if typeof(value) == TYPE_FLOAT:
        # PackedByteArray double is the actual 8-byte IEEE-754 payload,
        # independent of Godot Variant serializer implementation details.
        var bits: PackedByteArray = PackedByteArray()
        bits.resize(8)
        bits.encode_double(0, float(value))
        return {NATIVE_F64_TAG: Marshalls.raw_to_base64(bits)}
    if value is Dictionary:
        # A StringName key (as produced by some native N81 BT actions)
        # cannot be represented faithfully as a JSON object key. Keep
        # that small original Dictionary in a SHA-covered binary blob,
        # never drop/coerce its keys or paid contract identity.
        for key in value:
            if not (key is String):
                return {NATIVE_DICT_TAG: Marshalls.raw_to_base64(
                    var_to_bytes(value))}
        var output: Dictionary = {}
        for key in value:
            output[key] = _encode_native_f64(value[key], depth + 1)
        return output
    if value is Array:
        var output: Array = []
        for item in value:
            output.append(_encode_native_f64(item, depth + 1))
        return output
    return value

static func _decode_native_f64(value: Variant, state: Dictionary,
        depth: int = 0) -> Variant:
    if depth > MAX_NATIVE_DEPTH:
        state["ok"] = false
        return null
    if value is Dictionary:
        if value.has(NATIVE_DICT_TAG):
            if value.size() != 1 or not (value[NATIVE_DICT_TAG] is String):
                state["ok"] = false
                return null
            var packed: PackedByteArray = Marshalls.base64_to_raw(
                value[NATIVE_DICT_TAG])
            # Only tiny semantic dictionaries are encoded this way; do
            # not permit arbitrary native objects or unbounded blobs.
            if packed.is_empty() or packed.size() > 8192:
                state["ok"] = false
                return null
            var object: Variant = bytes_to_var(packed)
            if not (object is Dictionary) or var_to_bytes(object) != packed:
                state["ok"] = false
                return null
            return object
        if value.has(NATIVE_F64_TAG):
            if value.size() != 1 or not (value[NATIVE_F64_TAG] is String):
                state["ok"] = false
                return null
            var bytes: PackedByteArray = Marshalls.base64_to_raw(
                value[NATIVE_F64_TAG])
            # Exactly one binary64, never a serialized native object.
            if bytes.size() != 8:
                state["ok"] = false
                return null
            var restored: float = bytes.decode_double(0)
            if not is_finite(restored):
                state["ok"] = false
                return null
            return restored
        var output: Dictionary = {}
        for key in value:
            output[key] = _decode_native_f64(value[key], state, depth + 1)
            if not state["ok"]:
                return null
        return output
    if value is Array:
        var output: Array = []
        for item in value:
            output.append(_decode_native_f64(item, state, depth + 1))
            if not state["ok"]:
                return null
        return output
    return value


static func _canonical(value: Variant) -> String:
    if value is Dictionary:
        var keys: Array = value.keys()
        keys.sort()
        var parts: PackedStringArray = PackedStringArray()
        for key in keys:
            parts.append(JSON.stringify(str(key), "", true, true) + ":" + _canonical(value[key]))
        return "{" + ",".join(parts) + "}"
    if value is Array:
        var parts: PackedStringArray = PackedStringArray()
        for item in value:
            parts.append(_canonical(item))
        return "[" + ",".join(parts) + "]"
    return JSON.stringify(value, "", true, true)

static func _wrap(snapshot: Dictionary) -> Dictionary:
    # Hash the JSON-normalized payload, not GDScript integer/float variants:
    # JSON parsing may turn 7 into 7.0, and the digest must survive reload.
    # Every f64 in the checkpoint (orbits, calendar, original World,
    # N39 market history and ship state) uses exact binary64. Otherwise
    # a second JSON stringify of a P1 float can invalidate our payload
    # SHA despite the native frame itself being bit-preserved.
    # P1 bare saves and earlier untagged envelope payloads still decode.
    var transport: Variant = _encode_native_f64(snapshot)
    var normalized: Variant = JSON.parse_string(JSON.stringify(transport, "", true, true))
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
        # SHA authenticates the stored JSON BEFORE decoding the exact
        # binary64 tags. This handles both old plain v1 payloads and
        # new checkpoints, without an unverified lossy float promotion.
        var valid: Dictionary = {"ok": true}
        var restored: Variant = _decode_native_f64(payload, valid)
        if not valid["ok"] or not (restored is Dictionary):
            return {}
        return restored
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

## A SHA-valid primary is not necessarily a valid native World. Only a
## structurally plausible, coherent N38/N39/N9 snapshot may rotate over the
## last good .bak. Actual seed/runtime restorability belongs to TickRunner.
static func _trusted_for_backup_rotation(parsed: Dictionary) -> bool:
    if parsed.is_empty() or str(parsed.get("format", "")) != "living-sector-godot":
        return false
    if str(parsed.get("scenario", "")) != SourceTickRunner.SCENARIO_ID:
        return false
    var schema: Variant = parsed.get("schema_version", null)
    var tick: Variant = parsed.get("tick", null)
    if not _exact_nonnegative_whole(schema) or int(schema) != SourceTickRunner.SAVE_SCHEMA:
        return false
    if not _exact_nonnegative_whole(tick):
        return false
    if not (parsed.get("seed_fingerprint") is String) or str(parsed["seed_fingerprint"]).is_empty():
        return false
    if not (parsed.get("clock") is Dictionary) or not (
            parsed.get("orbital_angles") is Dictionary) or not (
            parsed.get("pending_controls") is Array):
        return false
    if parsed["pending_controls"].size() > 1024:
        return false
    # Ask the existing native clock/calendar/cadence/event validators. No
    # second live timeline is started; all objects are temporary read-only
    # preflight instances. This catches SHA-valid but nonrestorable clocks
    # and duplicate/expired source events before backup rotation.
    var clock := SourceClock.new()
    if not clock.restore(parsed["clock"]):
        return false
    var saved_calendar: Variant = parsed.get("calendar", null)
    if saved_calendar != null:
        if not (saved_calendar is Dictionary) or not SourceCalendar.new().restore(
                saved_calendar):
            return false
    var saved_cadence: Variant = parsed.get("cadence", null)
    if saved_cadence != null:
        if not (saved_cadence is Dictionary) or not SourceCadence.new().restore(
                saved_cadence, SourceTickRunner.NATIVE_PHASE_ORDER):
            return false
    var saved_events: Variant = parsed.get("events", null)
    if saved_events != null:
        if not (saved_events is Dictionary) or not SourceEvents.new().restore(
                saved_events, int(tick), SourceTickRunner.NATIVE_PHASE_ORDER.size()):
            return false
    return NativeCoherence.validate_serialized_candidate(parsed).get("ok", false) and \
        NativeTimeline.validate(parsed).get("ok", false)

static func _exact_nonnegative_whole(value: Variant) -> bool:
    if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
        return false
    var amount: float = float(value)
    return is_finite(amount) and amount >= 0.0 and (
        amount <= 9007199254740991.0) and amount == floorf(amount)

static func _physical_stock_matches(original: Dictionary, decoded: Dictionary) -> bool:
    # The unified N39 runtime owns market supply; SaveState must not silently
    # change any physical stock during the JSON round trip.
    if not original.has("native_production"):
        return true # Legacy P1 snapshots have no N39 market state.
    if not (decoded.get("native_production") is Dictionary):
        return false
    var original_native: Variant = original["native_production"]
    var decoded_native: Dictionary = decoded["native_production"]
    if not (original_native is Dictionary):
        return false
    var original_world: Variant = original_native.get("world")
    var decoded_world: Variant = decoded_native.get("world")
    if not (original_world is Dictionary) or not (decoded_world is Dictionary):
        return false
    var original_markets: Variant = original_world.get("markets")
    var decoded_markets: Variant = decoded_world.get("markets")
    if not (original_markets is Dictionary) or not (decoded_markets is Dictionary):
        return false
    if original_markets.size() != decoded_markets.size():
        return false
    for market_id in original_markets:
        if not decoded_markets.has(market_id):
            return false
        var before: Variant = original_markets[market_id]
        var after: Variant = decoded_markets[market_id]
        if not (before is Dictionary) or not (after is Dictionary):
            return false
        if not (before.get("supply") is Dictionary) or not (after.get("supply") is Dictionary):
            return false
        if before["supply"] != after["supply"]:
            return false
    return true

## Exact UTF-8 byte measurement of the actual N38 v1 envelope. This is
## diagnostic only: no file I/O, no archive migration and no limit increase.
## The same encoder is used by save_runner, including tabs and final newline.
static func encoded_checkpoint_bytes(snapshot: Dictionary) -> int:
    return _encode_checkpoint_text(snapshot).to_utf8_buffer().size()

static func _encode_checkpoint_text(snapshot: Dictionary) -> String:
    return JSON.stringify(_wrap(snapshot), "\t", true, true) + "\n"

static func encoded_checkpoint_budget(snapshot: Dictionary) -> Dictionary:
    var count: int = encoded_checkpoint_bytes(snapshot)
    return {"encoded_bytes": count, "max_bytes": MAX_SAVE_BYTES,
        "remaining_bytes": maxi(0, MAX_SAVE_BYTES - count),
        "within_limit": count <= MAX_SAVE_BYTES}

## Last actual save attempt's serialized UTF-8 size. Updated from the SAME
## buffer that is written to .pending; no second checkpoint traversal.
## -1 means no encoding attempt in this process. Diagnostic only.
static var _last_save_encoded_bytes: int = -1
# Actual CPU-side UTF-8 encoding wall duration of the last attempted save.
# This measures only the real N38 encode, not checkpoint() or disk/validation.
# -1 means no encoding has been attempted; diagnostics do not reserialize.
static var _last_save_encode_usec: int = -1

static func last_save_encoded_bytes() -> int:
    return _last_save_encoded_bytes

static func last_save_encode_usec() -> int:
    return _last_save_encode_usec

## Preserve the previous known-good backup until the new primary is safely
## promoted. The old path deleted .bak BEFORE renaming primary to .bak; a
## failed rename could therefore destroy the only usable recovery checkpoint.
## .bak.previous is an interrupted-rotation recovery candidate, not a new
## checkpoint format. Never overwrite an orphaned previous backup blindly.
## Repair a crash between parking the old backup and completing rotation.
## Only the already-verified N38 checkpoints can authorize deletion. A valid
## .bak takes precedence over the older .bak.previous; if .bak is corrupt,
## restore the older verified copy before attempting another save.
## Called only after the new .pending has passed full roundtrip validation.
static func _reconcile_parked_backup(absolute_path: String,
        primary_valid: bool, backup_valid: bool,
        previous_valid: bool) -> Error:
    var backup: String = absolute_path + ".bak"
    var previous: String = absolute_path + ".bak.previous"
    if not FileAccess.file_exists(previous):
        return OK
    if backup_valid:
        # The current backup is already a verified recoverable checkpoint.
        return DirAccess.remove_absolute(previous)
    if previous_valid:
        # Never remove the last valid recovery copy before promotion.
        # A failed rename leaves the verified .previous intact.
        if FileAccess.file_exists(backup):
            var remove_bad: Error = DirAccess.remove_absolute(backup)
            if remove_bad != OK:
                return remove_bad
        return DirAccess.rename_absolute(previous, backup)
    if not primary_valid:
        # All three candidates are invalid: keep every byte for diagnosis.
        return ERR_FILE_CORRUPT
    # Primary is verified; both recovery copies are invalid. Discard them
    # before rotating the healthy primary, never park corrupt .bak again.
    var remove_previous: Error = DirAccess.remove_absolute(previous)
    if remove_previous != OK:
        return remove_previous
    if FileAccess.file_exists(backup):
        return DirAccess.remove_absolute(backup)
    return OK


static func _promote_verified_pending(absolute_path: String,
        primary_is_valid: bool) -> Error:
    var pending: String = absolute_path + ".pending"
    var backup: String = absolute_path + ".bak"
    var previous: String = absolute_path + ".bak.previous"
    var had_primary: bool = FileAccess.file_exists(absolute_path)
    var parked_backup: bool = false
    if had_primary and primary_is_valid:
        if FileAccess.file_exists(previous):
            return ERR_ALREADY_EXISTS
        if FileAccess.file_exists(backup):
            var park_error: Error = DirAccess.rename_absolute(backup, previous)
            if park_error != OK:
                return park_error
            parked_backup = true
        var rotate_error: Error = DirAccess.rename_absolute(absolute_path, backup)
        if rotate_error != OK:
            if parked_backup:
                DirAccess.rename_absolute(previous, backup)
            return rotate_error
    elif had_primary:
        var remove_error: Error = DirAccess.remove_absolute(absolute_path)
        if remove_error != OK:
            return remove_error
    var promote_error: Error = DirAccess.rename_absolute(pending, absolute_path)
    if promote_error != OK:
        if had_primary and primary_is_valid:
            DirAccess.rename_absolute(backup, absolute_path)
            if parked_backup:
                DirAccess.rename_absolute(previous, backup)
        return promote_error
    # A crash before this cleanup is safe: primary and backup are valid.
    # A later save refuses to overwrite the orphan until recovery resolves it.
    if parked_backup:
        DirAccess.remove_absolute(previous)
    return OK


static func save_runner(runner: RefCounted, save_path: String = DEFAULT_PATH) -> Error:
    if not runner.is_started():
        return ERR_INVALID_DATA
    var snapshot: Dictionary = runner.checkpoint()
    if snapshot.is_empty():
        return ERR_INVALID_DATA
    # Before serializing, confirm the ONE World and N9 ledger are the same
    # transaction frame, receipts do not claim future ticks, and P1 events
    # have not already expired. Do not write .pending on inconsistent input.
    var native_coherence: Dictionary = NativeCoherence.validate(snapshot)
    if not native_coherence.get("ok", false) or not (
            NativeTimeline.validate(snapshot).get("ok", false)):
        return ERR_INVALID_DATA
    var absolute_path: String = ProjectSettings.globalize_path(save_path)
    var folder: String = absolute_path.get_base_dir()
    var mkdir_result: Error = DirAccess.make_dir_recursive_absolute(folder)
    if mkdir_result != OK:
        return mkdir_result

    # A previously interrupted load promotion must not indefinitely block
    # later verified pending saves. Only a trusted primary can authorize
    # discarding its displaced predecessor.
    var displaced_result: Error = _reconcile_recovery_displaced(absolute_path)
    if displaced_result != OK:
        return displaced_result
    var tmp: String = absolute_path + ".pending"
    var backup: String = absolute_path + ".bak"
    # Encode the actual on-disk UTF-8 payload once. The N38 size limit
    # applies to bytes, not String length; reuse the measured buffer for
    # writing instead of allocating a second full UTF-8 copy.
    var encode_started_usec: int = Time.get_ticks_usec()
    var encoded_bytes: PackedByteArray = _encode_checkpoint_text(snapshot).to_utf8_buffer()
    _last_save_encode_usec = Time.get_ticks_usec() - encode_started_usec
    _last_save_encoded_bytes = encoded_bytes.size()
    if encoded_bytes.size() > MAX_SAVE_BYTES:
        return ERR_OUT_OF_MEMORY
    var file := FileAccess.open(tmp, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_buffer(encoded_bytes)
    file.flush()
    var write_error: Error = file.get_error()
    file.close()
    if write_error != OK:
        DirAccess.remove_absolute(tmp)
        return write_error
    # The file is not a safe replacement merely because its SHA-256 matches:
    # both writer and reader can agree on a lossy JSON representation. Compare
    # physical market inventories against the live checkpoint BEFORE promotion.
    var verified: Dictionary = _read_checkpoint(tmp)
    # A valid N38 SHA256 still cannot guarantee native economic fidelity
    # if JSON rounded a credit, escrow, cargo amount or receipt before hash.
    # Fail closed BEFORE replacing a valid primary/.bak save.
    var native_frame_check: Dictionary = NativeFrameGuard.verify_authoritative_frame(
        snapshot, verified)
    if verified.is_empty() or not _physical_stock_matches(snapshot, verified) or \
            not native_frame_check.get("ok", false):
        DirAccess.remove_absolute(tmp)
        return ERR_FILE_CORRUPT

    var primary_is_valid: bool = false
    if FileAccess.file_exists(absolute_path):
        primary_is_valid = _trusted_for_backup_rotation(
            _read_checkpoint(absolute_path))
    # A previous interrupted rotation must not permanently block saves.
    # Validate both recovery candidates using the same N38 restore preflight
    # as primary rotation. No unchecked file is promoted or deleted.
    var previous_path: String = absolute_path + ".bak.previous"
    if FileAccess.file_exists(previous_path):
        var backup_valid: bool = FileAccess.file_exists(backup) and (
            _trusted_for_backup_rotation(_read_checkpoint(backup)))
        var previous_valid: bool = _trusted_for_backup_rotation(
            _read_checkpoint(previous_path))
        var recovery_result: Error = _reconcile_parked_backup(
            absolute_path, primary_is_valid, backup_valid, previous_valid)
        if recovery_result != OK:
            return recovery_result
    var promote_result: Error = _promote_verified_pending(
        absolute_path, primary_is_valid)
    if promote_result != OK:
        # The verified pending checkpoint remains available for recovery.
        # Never discard it after a failed filesystem rotation.
        return promote_result
    return OK


## Recovery promotion must not delete an existing primary before the
## recovered checkpoint is installed. A failed rename restores the original
## bytes, and a crash after parking remains recoverable on the next launch.
## This path is used only after the real Runner accepted the candidate.
## Recover an interrupted recovery promotion without losing the only good
## checkpoint. A displaced original is retained until the promoted primary
## has been accepted by the actual runner, not merely by its SHA envelope.
static func _reconcile_recovery_displaced(absolute_path: String) -> Error:
    var displaced: String = absolute_path + ".recovery-displaced"
    if not FileAccess.file_exists(displaced):
        return OK
    if not FileAccess.file_exists(absolute_path):
        # Never destroy the only surviving checkpoint. load_runner will
        # restore and promote this candidate after full Runner validation.
        return OK
    if not _trusted_for_backup_rotation(_read_checkpoint(absolute_path)):
        # An invalid primary must not authorize deleting the displaced copy.
        return OK
    return DirAccess.remove_absolute(displaced)


## Recovery promotion must not delete an existing primary before the
## recovered checkpoint is installed. A failed rename restores the original
## bytes, and a crash after parking remains recoverable on the next launch.
## This path is used only after the real Runner accepted the candidate.
static func _promote_recovered_checkpoint(absolute_path: String,
        candidate: String) -> bool:
    var displaced: String = absolute_path + ".recovery-displaced"
    var rejected: String = absolute_path + ".recovery-rejected"
    if candidate == absolute_path or not FileAccess.file_exists(candidate):
        return false
    var candidate_is_displaced: bool = candidate == displaced
    # A normal pending/previous promotion cannot overwrite an interrupted
    # prior recovery. Its orphan remains an independent load candidate.
    if not candidate_is_displaced and FileAccess.file_exists(displaced):
        return false
    # When promoting the orphan itself, park the rejected primary elsewhere.
    # Never overwrite an earlier rejected file without explicit recovery.
    var parking: String = rejected if candidate_is_displaced else displaced
    if FileAccess.file_exists(parking):
        return false
    var had_primary: bool = FileAccess.file_exists(absolute_path)
    if had_primary:
        if DirAccess.rename_absolute(absolute_path, parking) != OK:
            return false
    var promotion: Error = DirAccess.rename_absolute(candidate, absolute_path)
    if promotion != OK:
        if had_primary:
            # A failed rollback still leaves the original in a recoverable
            # named file, never silently deletes its bytes.
            DirAccess.rename_absolute(parking, absolute_path)
        return false
    if had_primary:
        # Only discard a displaced primary after the candidate was restored.
        # If it was invalid, preserve it for diagnostics until a later save.
        if not candidate_is_displaced:
            DirAccess.remove_absolute(parking)
    return true

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
    for candidate in [absolute_path, absolute_path + ".bak",
            absolute_path + ".bak.previous", absolute_path + ".pending",
            absolute_path + ".recovery-displaced",
            absolute_path + ".recovery-rejected"]:
        var parsed: Dictionary = _read_checkpoint(candidate)
        if parsed.is_empty() or not NativeTimeline.validate(parsed).get("ok", false):
            continue
        if runner.restore_checkpoint(parsed, seed):
            # A verified pending checkpoint was fully restored after an
            # interrupted save. Promote it for the next application launch,
            # otherwise a subsequent restart may load the older .bak instead.
            # Never touch a valid primary or the last good backup.
            var promoted_pending: bool = false
            var promoted_previous: bool = false
            if candidate == absolute_path + ".pending":
                promoted_pending = _promote_recovered_checkpoint(
                    absolute_path, candidate)
            elif candidate == absolute_path + ".bak.previous":
                promoted_previous = _promote_recovered_checkpoint(
                    absolute_path, candidate)
            elif candidate == absolute_path + ".recovery-displaced":
                _promote_recovered_checkpoint(absolute_path, candidate)
            elif candidate == absolute_path + ".recovery-rejected":
                # A rejected original can still be the last valid save after
                # an interrupted promotion. Restore it without overwriting
                # any other candidate until the next verified save.
                pass
            elif candidate == absolute_path:
                # A successful live restore is stronger than envelope-only
                # validation; an orphaned prior primary is no longer needed.
                _reconcile_recovery_displaced(absolute_path)
            return {
                "ok": true,
                "source": candidate,
                "tick": runner.tick_count,
                "recovered_pending": candidate == absolute_path + ".pending",
                "promoted_pending": promoted_pending,
                "promoted_previous": promoted_previous
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
