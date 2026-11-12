# N33 — приёмка интеграционной ветки Godot

Статус: **CODE_UNVERIFIED**. Основа: N32 PR #120, SHA f7e3709dab88cf1fb6dcf1b0580d3c49409abffb.

## Существенные изменения

1. Быстрый обязательный набор 11 тестов: отсутствие файла означает FAIL, а не молчаливый пропуск.
2. Отдельная проверка импорта проекта Godot в headless editor и выполнение тестов с индивидуальными логами.
3. FAIL при ненулевом exit code либо при ERROR/PARSE ERROR/SCRIPT ERROR/_FAIL в логах даже при ошибочном quit(0).
4. Режим all автоматически обнаруживает *_check.gd и *_smoke.gd вместо устаревающего ручного перечня.
5. Машинный summary.json и человекочитаемый summary.txt; отсутствие Godot возвращает exit 2 и явный FAIL.

## Windows

Скачать полный ZIP этой ветки вместе с native/priv/galaxy/data. Скачать Godot 4 Standard (не .NET), положить exe в godot/Godot.exe или указать GODOT_EXE. Запустить godot/RUN-INTEGRATION-ACCEPTANCE.cmd; затем godot/RUN-INTEGRATION-ACCEPTANCE.cmd all. Результаты: godot/logs/integration-acceptance/.

## Границы

Это тестовый стенд, не доказательство готовности экономики и ИИ. Текущий авторитетный TickRunner в N32 всё ещё выполняет только орбиты; для интеграции нужны реальные экономические тики и Rust golden parity. В агентской среде Godot и Windows PowerShell недоступны: тесты и сам скрипт здесь НЕ запускались. Использованы только встроенные PowerShell 5.1 и Godot, сторонних лицензий нет. Следующий этап — исправить фактические runtime ошибки и добавить контрольные сценарии.
