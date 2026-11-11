# Living Sector — Sol Relief S0: обследование реальной экономики

**Цель:** проверить, какие данные Genesis действительно предоставляет для цепочки
pressure → goal → funded contract → picked_up → delivered → relief.

Это **только S0**, не подтверждение Golden-v1 и не новая игровая механика.

## Проверенная основа

Используется готовый Windows-архив Galaxy 0.6.2 из успешного
GitHub Actions run 42990801593. Источник: SHA
4ffd80002ec74b4af3eccb0db5279578c1148e0a.
Ветка S0 не содержит новую 0.6.3 и не изменяет Unity/Rust, Observer,
код ИИ или существующие сохранения.

## Как работает

1. GitHub Actions скачивает уже созданный Windows portable ZIP.
2. На чистой временной SQLite запускается реальный Genesis с hybrid/execute/x16.
3. Каждые ~120 тиков до ~1800 тиков сохраняется реальный снимок
   /api/health, /api/report, /api/strategy, /api/contracts.
4. Отдельно сохраняются реально полученные события /ws и журнал сервера.
5. Анализатор отмечает точные observed tick/time для earth-station,
   Genesis и food/water/fuel; отсутствующие данные остаются null/unknown.

## Выход

- manifest.json: версия сборки, SHA256 бинарника, fresh DB и параметры.
- samples.jsonl: настоящие снимки API.
- events.jsonl: реальные наблюдавшиеся WS-события.
- signal-inventory.json: обнаруженные ключи и возможные proof signals.
- result.json: раздельные t_pressure/t_goal/t_funded/t_pickup/t_delivered,
  фактические количества только если они есть в API, блокеры.
- REPORT-RU.md: русский итог без ложных заявлений об успехе.

## Строгие границы

- Прогноз ИИ, HTTP 202 и статусы контракта не создают материальные ресурсы.
- paid — не доставка.
- Контракт на другой станции не считается снабжением earth-station.
- t_pressure на market stock < demand считается наблюдаемым рыночным
  давлением, но не подменяет server shortage_ticks.
- delivery_verified требует фактически увиденные упорядоченные этапы
  native funding/pickup/delivered и явное число delivered_units.
  Если API не содержит всех полей, не объявлять false failure экономики —
  пометить пробел измерения.
- relief_verified = unknown, пока нет проверенной причинной связи с
  native market receipt или детерминированным A/B baseline.
  Рост склада мог быть вызван фермой или падением потребления.
- resilience_verified = not_tested: повторные кризисы — другой milestone.

## Acceptance

Первый S0 успешен как **измерение**, если Windows Genesis с fresh DB
дошёл до заданного тика, сохранил сырой trace и manifest, а анализатор
явно показывает обнаруженные поля, отсутсвующие сигналы и блокеры.
Отсутствие дефицита в коротком прогоне — не баг само по себе;
после инвентаризации возможна отдельная pressure fixture.

После S0: проверить реальную native delivery attribution и baseline,
три независимых fresh-DB прогона Sol-Relief-Golden-v1,
затем исправлять обнаруженные обрывы и переводить ZIP+overlays
в полноценный ревьюируемый source snapshot.

Другие фракции, исследования T2/T3, масштаб галактики и идея
управления через главу/администраторов не отменяются.
