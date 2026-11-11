extends RefCounted
## Read the SAME JSON data as native Genesis; do not invent new world content.
## During development the Godot project sits next to native/ in this repository.
## A portable export will eventually package a verified copy under res://data/.
##
## No simulation mechanics have been ported by this loader.

static func load_current_world() -> Dictionary:
    var paths: Array[String] = [
        ProjectSettings.globalize_path("res://data/galaxy"),
        ProjectSettings.globalize_path("res://../native/priv/galaxy/data")
    ]
    for base in paths:
        if not DirAccess.dir_exists_absolute(base):
            continue
        var faction_path: String = base.path_join("factions.json")
        if not FileAccess.file_exists(faction_path):
            continue
        var factions_value: Variant = JSON.parse_string(
            FileAccess.get_file_as_string(faction_path)
        )
        if not (factions_value is Array):
            return {"error": "Некорректный factions.json: " + faction_path}
        var world_folder: String = base.path_join("worlds")
        if not DirAccess.dir_exists_absolute(world_folder):
            return {"error": "Не найдена папка worlds: " + world_folder}
        var worlds: Array = []
        var filenames: PackedStringArray = DirAccess.get_files_at(world_folder)
        filenames.sort()
        for filename in filenames:
            if not filename.ends_with(".json"):
                continue
            var value: Variant = JSON.parse_string(
                FileAccess.get_file_as_string(world_folder.path_join(filename))
            )
            if not (value is Dictionary) or not value.has("system"):
                return {"error": "Некорректный мир: " + filename}
            worlds.append(value)
        return {"factions": factions_value, "worlds": worlds, "source": base}
    return {"error": "Нативные JSON не найдены. Откройте Godot-проект рядом с папкой native/."}
