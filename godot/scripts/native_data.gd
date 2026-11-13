extends RefCounted
## Strict P0 adapter for the unchanged Galaxy 0.6.7 JSON.
## This is an importer, NOT a new economy, world generator or simulation.
## Does not fall back to old six-system Genesis/C1 data silently.

const EXPECTED_SYSTEMS = [
    "system-alpha-centauri", "system-barnard", "system-epsilon-eridani",
    "system-lalande", "system-nadir", "system-sol", "system-tau-ceti",
    "system-vega"
]
const EXPECTED_FACTIONS = ["terran-authority", "pirates", "ceti-freeholds"]

static func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"error": "Отсутствует файл: " + path}
    var parser := JSON.new()
    var result: Error = parser.parse(FileAccess.get_file_as_string(path))
    if result != OK:
        return {"error": "Неверный JSON %s (строка %d): %s" % [
            path, parser.get_error_line(), parser.get_error_message()
        ]}
    return {"value": parser.data}

static func load_current_world() -> Dictionary:
    var project_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
    var repo_root: String = project_dir.get_base_dir()
    # In an exported Windows build, res:// points into the PCK; the original
    # Rust Galaxy JSON seed is shipped as external, unchanged files beside
    # LivingSector.exe. Do not depend on the developer repository existing.
    var executable_dir: String = OS.get_executable_path().get_base_dir()
    var candidates: Array[String] = [
        project_dir.path_join("data/galaxy"),
        repo_root.path_join("native/priv/galaxy/data"),
        executable_dir.path_join("data/galaxy")
    ]
    for base in candidates:
        if DirAccess.dir_exists_absolute(base):
            return _load_exact_galaxy(base)
    return {"error": "Не найден именно Galaxy 0.6.7. Требуется папка data/galaxy рядом с LivingSector.exe (или исходный native/priv/galaxy/data). Другие миры не подставляются."}

static func _load_exact_galaxy(base: String) -> Dictionary:
    var checked_factions: Dictionary = _read_json(base.path_join("factions.json"))
    if checked_factions.has("error"):
        return checked_factions
    var factions_value: Variant = checked_factions["value"]
    if not (factions_value is Array):
        return {"error": "factions.json: ожидается массив"}
    var factions: Array = factions_value
    var faction_ids: Dictionary = {}
    for faction in factions:
        if not (faction is Dictionary):
            return {"error": "factions.json содержит не объект"}
        var id: String = str(faction.get("id", ""))
        if id.is_empty() or faction_ids.has(id):
            return {"error": "Пустой или повторяющийся ID фракции: " + id}
        faction_ids[id] = true
    if faction_ids.size() != EXPECTED_FACTIONS.size():
        return {"error": "Для этого эталона требуются 3 фракции, найдено %d" % faction_ids.size()}
    for id in EXPECTED_FACTIONS:
        if not faction_ids.has(id):
            return {"error": "Отсутствует фракция эталона: " + id}

    var world_folder: String = base.path_join("worlds")
    if not DirAccess.dir_exists_absolute(world_folder):
        return {"error": "Отсутствует папка worlds: " + world_folder}
    var filenames: PackedStringArray = DirAccess.get_files_at(world_folder)
    filenames.sort()
    var worlds: Array = []
    var system_ids: Dictionary = {}
    var body_ids: Dictionary = {}
    var facility_ids: Dictionary = {}
    var total_ships: int = 0
    var total_markets: int = 0
    var total_populations: int = 0
    var source_files: Array[String] = ["factions.json"]
    for filename in filenames:
        if not filename.ends_with(".json"):
            continue
        var loaded: Dictionary = _read_json(world_folder.path_join(filename))
        if loaded.has("error"):
            return loaded
        var value: Variant = loaded["value"]
        if not (value is Dictionary):
            return {"error": filename + ": корень должен быть объектом"}
        var system_value: Variant = value.get("system", null)
        if not (system_value is Dictionary):
            return {"error": filename + ": нет объекта system"}
        var system: Dictionary = system_value
        var system_id: String = str(system.get("id", ""))
        var offset: Variant = system.get("universe_offset", null)
        if system_id.is_empty() or system_ids.has(system_id):
            return {"error": "Пустой или повторный system.id в " + filename}
        if not (offset is Array) or offset.size() != 2:
            return {"error": filename + ": нет координат из двух чисел"}
        if not ((offset[0] is int or offset[0] is float) and
                (offset[1] is int or offset[1] is float)):
            return {"error": filename + ": координаты должны быть числовыми"}
        for key in ["bodies", "facilities", "ships", "populations", "markets",
                    "travel_routes", "nav_sites"]:
            if not (value.get(key, null) is Array):
                return {"error": filename + ": отсутствует массив " + key}
        for body in value["bodies"]:
            if not (body is Dictionary):
                return {"error": filename + ": некорректное небесное тело"}
            var body_id: String = str(body.get("id", ""))
            if body_id.is_empty() or body_ids.has(body_id):
                return {"error": "Повторный ID тела: " + body_id}
            # P1 mutates only these native orbit values; fail before the model
            # is built instead of converting malformed JSON to a fake zero orbit.
            var orbit_period: Variant = body.get("orbit_period", null)
            var current_angle: Variant = body.get("current_angle", null)
            if not (orbit_period is int or orbit_period is float) or not (current_angle is int or current_angle is float):
                return {"error": filename + ": у тела " + body_id + " нет числовой орбиты"}
            if not is_finite(float(orbit_period)) or float(orbit_period) <= 0.0:
                return {"error": filename + ": некорректный orbit_period у " + body_id}
            if not is_finite(float(current_angle)) or float(current_angle) < 0.0 or float(current_angle) >= 360.0:
                return {"error": filename + ": некорректный current_angle у " + body_id}
            body_ids[body_id] = true
        for facility in value["facilities"]:
            if not (facility is Dictionary):
                return {"error": filename + ": некорректное предприятие"}
            var facility_id: String = str(facility.get("id", ""))
            if facility_id.is_empty() or facility_ids.has(facility_id):
                return {"error": "Повторный ID предприятия: " + facility_id}
            if not faction_ids.has(str(facility.get("faction_id", ""))):
                return {"error": "Неизвестный владелец предприятия: " + facility_id}
            facility_ids[facility_id] = true
        for ship in value["ships"]:
            if not (ship is Dictionary) or not faction_ids.has(str(ship.get("faction_id", ""))):
                return {"error": filename + ": корабль без существующей фракции"}
        system_ids[system_id] = true
        worlds.append(value)
        source_files.append("worlds/" + filename)
        total_ships += value["ships"].size()
        total_markets += value["markets"].size()
        total_populations += value["populations"].size()

    if system_ids.size() != EXPECTED_SYSTEMS.size():
        return {"error": "В Galaxy 0.6.7 должны быть 8 систем, найдено %d" % system_ids.size()}
    for id in EXPECTED_SYSTEMS:
        if not system_ids.has(id):
            return {"error": "Отсутствует обязательная система: " + id}
    # Preserve original seed arrays and IDs. The main UI receives read-only copies.
    return {
        "factions": factions, "worlds": worlds, "source": base,
        "source_files": source_files,
        "seed_stats": {
            "systems": worlds.size(), "factions": factions.size(),
            "bodies": body_ids.size(), "facilities": facility_ids.size(),
            "ships": total_ships, "markets": total_markets,
            "populations": total_populations
        }
    }
