extends RefCounted
## Versioned Godot FileAccess save for the P1 orbital-only state.
## Never changes original Rust SQLite or world JSON files.
## Atomic temp->primary promotion with recoverable .bak if an old save exists.

const DEFAULT_PATH: String = "user://saves/galaxy-067-p1.json"

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
    var file := FileAccess.open(tmp, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(snapshot, "\t") + "\n")
    file.flush()
    file.close()
    # Validate our full output before touching the existing save.
    var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string(tmp))
    if not (candidate is Dictionary) or candidate.get("schema_version", null) == null:
        DirAccess.remove_absolute(tmp)
        return ERR_FILE_CORRUPT

    var had_primary: bool = FileAccess.file_exists(absolute_path)
    if had_primary:
        if FileAccess.file_exists(backup):
            var remove_result: Error = DirAccess.remove_absolute(backup)
            if remove_result != OK:
                DirAccess.remove_absolute(tmp)
                return remove_result
        var backup_result: Error = DirAccess.rename_absolute(absolute_path, backup)
        if backup_result != OK:
            DirAccess.remove_absolute(tmp)
            return backup_result

    var promote_result: Error = DirAccess.rename_absolute(tmp, absolute_path)
    if promote_result != OK:
        if had_primary:
            DirAccess.rename_absolute(backup, absolute_path)
        return promote_result
    return OK

static func load_runner(runner: RefCounted, seed: Dictionary,
        save_path: String = DEFAULT_PATH) -> Dictionary:
    if not runner.is_started():
        return {"ok": false, "error": "Simulation is not initialized"}
    var absolute_path: String = ProjectSettings.globalize_path(save_path)
    for candidate in [absolute_path, absolute_path + ".bak"]:
        if not FileAccess.file_exists(candidate):
            continue
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
        if not (parsed is Dictionary):
            continue
        if runner.restore_checkpoint(parsed, seed):
            return {"ok": true, "source": candidate, "tick": runner.tick_count}
    return {
        "ok": false,
        "error": "Save is missing, incompatible, incomplete or corrupted; live world unchanged"
    }
