# Какая версия игрового мира переносится в Godot

Источник истины — **`native/priv/galaxy/data/`** замороженной Rust Galaxy 0.6.7, commit `6e40615be95cc6ddbabe21c3b94def5c52f8622d`. Никакой автоматической подмены другим набором.

## Фактическая структура Galaxy 0.6.7 (проверена по JSON из GitHub)

- 8 систем: `system-alpha-centauri`, `system-barnard`, `system-epsilon-eridani`, `system-lalande`, `system-nadir`, `system-sol`, `system-tau-ceti`, `system-vega`.
- 3 фракции: `terran-authority` (игровое имя Genesis Initiative), `pirates`, `ceti-freeholds`. **Не заменять ID на display name**, это сломает ссылки/отношения.
- Начальные seed-объекты: **47 тел, 15 facilities, 24 корабля, 3 населения, 3 рынка**. Это исходные записи JSON, а не результат тика; число живых объектов может меняться в игре.
- 8 JSON `worlds/`, отдельные `factions.json`, `resource_grades.json`, `tuning.json`.
- ID всех восьми систем, 47 тел и 15 facilities уникальны в просмотренном наборе.
- `resource_grades.json` содержит `active: false`: его наличие **не включает** добычу по качеству залежей.

| Мир | ID | Координаты | Тел | Предприятий/станций | Кораблей |
|---|---|---|---:|---:|---:|
| Alpha Centauri | system-alpha-centauri | (40, 10) | 5 | 5 | 8 |
| Barnard | system-barnard | (110, -110) | 4 | 0 | 0 |
| Epsilon Eridani | system-epsilon-eridani | (64, -96) | 5 | 0 | 0 |
| Lalande | system-lalande | (160, -90) | 4 | 0 | 0 |
| Nadir | system-nadir | (255, -190) | 6 | 5 | 8 |
| Sol | system-sol | (0, 0) | 13 | 5 | 8 |
| Tau Ceti | system-tau-ceti | (80, -20) | 6 | 0 | 0 |
| Vega | system-vega | (120, -60) | 4 | 0 | 0 |

Схема `worlds/*.json`: `system`, `bodies`, `travel_routes`, `facilities`, `markets`, `ships`, `populations`, `nav_sites`. Пробелы между физическими системами задаются `system.universe_offset`. Дистанции `travel_routes[].distance` относятся к маршрутам между **локациями** — это **не расстояние в световых годах**, и длину нарисованной линии между системами нельзя напрямую принимать за маршрут. Нативный `WorldRegistry` хранит стоимость ребра отдельно.

## Остальные наборы тоже сохраняем

| Папка | Систем | Назначение |
|---|---:|---|
| `native/priv/genesis/data/` | 6 | Более ранний старт Genesis; отдельный сценарий, **не смешивать с Galaxy** |
| `native/priv/data/` | 6 | Legacy/базовые данные C1; отдельный исходник |
| `priv/data/` | 6 | Корневой исторический вариант; значения world JSON совпадают blob SHA с `native/priv/data/` |
| `native/priv/galaxy/data/` | 8 | **Текущий целевой мир Godot** |

У каждой альтернативы отдельный ID сценария. Если понадобится переключение, добавим явный выбор стартового набора и версионированный manifest. До того Godot читает только Galaxy: локально скопированную `res://data/galaxy/` или соседнюю `native/priv/galaxy/data/`.

## Приёмка

- В отладочном импорте отклонять повреждённый JSON, повторяющиеся ID, отсутствие любой из восьми систем, нарушение состава фракций. **Не «лечить» файл выдуманными сущностями**.
- `world_data` остаётся неизменным после отображения карты. Хозяйственные тики не запускаются автоматически, пока экономический модуль не перенесён.
- Проверка seed JSON/гит-хешей проведена без Godot. **Запуск и визуальная приёмка в Godot пока не подтверждены**.
