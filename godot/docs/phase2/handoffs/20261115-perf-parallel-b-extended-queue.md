# Living Sector Performance — Chat B | 8-block execution backlog

**СТАТУС: ПОДГОТОВЛЕНО, БЛОКИ НЕ НАЧАТЫ.** Не путать эту очередь с готовыми исправлениями. PR: https://github.com/Mefits/Living-Sector/pull/258 (Draft). Ветка: `feature/perf-parallel-b-n153-indices-20261115`.

Общий регламент с закреплённым владением: https://github.com/Mefits/Living-Sector/blob/integration/godot-phase2-unified-20261113/godot/docs/phase2/handoffs/20261115-performance-parallel-two-chats.md

Доска: https://www.tldraw.com/f/Dzo-huxLVMxka2COuru0w, вкладка **«Оптимизация»**, исключительно дорожка ЧАТ №2.

Исходный проверенный SHA: `2915ba07e1f17f86e63f21c904288a9b70c11423`; общий docs-only SHA: `823f32379b10bfefae5a5cebb1c0c0e622509f72`. Перед каждой рабочей итерацией проверять свежие SHA и lease чата A.

## Таблица прогресса (честно обновлять после каждого блока)

| ID | Статус | Коммит / тест | Решение |
| --- | --- | --- | --- |
| B1 | TODO | — | N153 baseline / hot counters |
| B2 | TODO | — | Immutable per-call eligible ship roster |
| B3 | TODO | — | Indexed posted delivery offers, expiry |
| B4 | TODO | — | Eligibility filters by location/faction/cargo |
| B5 | TODO | — | DTO/knowledge/funding projections + decision parity |
| B6 | TODO | — | N18 station admin roster indexing if measured |
| B7 | TODO | — | EventQueue bucket/heap *only if measured* |
| B8 | TODO | — | Valid 24/100/500 fixtures + integration 420/900, A/B |

### B1 — N153 source baseline and observability
На реальном original world описать вложенный цикл `unified_n153_contract_dispatch.gd::propose()`: contract ID / ship ID sort, сколько contract×ship пар реально проверяются, какие причины отказа преобладают, сколько раз запускается `_ready_ship` / `N153.select_contract` / `NativePipeline.propose`, path-cache hits и цена вызовов. Измерить ticks, профиль, p95; получить baseline SHA. Результат: таблица с реальной трудоёмкостью, не только оценка сложности O(C×S).

### B2 — безопасные неизменяемые ship rosters на один propose()
Построить call-scoped отсортированный roster из исходных `world["ships"]` (busy/available, locations, capacity, faction), без кеша между независимыми тиками. Сохранить исходную последовательность **contract ID → ship ID** даже после фильтрации. Самый важный инвариант — точные `ship_rejection_counts`, `blocked`, `already_assigned`, отказное `reason`. Если быстрый skip меняет counts, сохранять equivalent recorded reason или не применять skip. Никакого приоритета по profit, отличного от frozen source.

### B3 — активные posted delivery contracts и expiry
Индекс/проекция active offers по `status=posted`, `contract_type=delivery`, expiry. Сортировка contract IDs сохраняет source lexicographic order; истекшие offers должны остаться в `blocked` там, где исходный код их добавлял. Не исчезает `market_missing`, `source_owner_missing` и прочие contract-level gate causes. Инвалидировать на новом `propose`; persistent index не вводить без строгой версии N38/World.

### B4 — per-call eligibility by location/faction/cargo, no invented permission
Индексировать дешевую реальную проверку locations, faction, cargo capacity и idle/dock state. Плата, fuel entire directed route, sensor, real observed price knowledge, reputation/posture, stock и valid source funds всегда проверяются против *текущего* мира на финальном этапе. Сохранять denied outcomes; найденный false positive должен отвергаться исходным validator, false negative недопустим. Сохранить tie-breaking `profit >` и порядок ship IDs. Не трогать кеш N4 `route_graph.gd` (PR #254 уже решил повторные запросы).

### B5 — убрать повторную подготовку неизменных N153 context DTO
На одной итерации `propose` переиспользовать только действительно immutable data по (contract/source/dest): `systems`, quotes, market/owner/faction, sensor class defaults; не копировать полную `price_knowledge` без необходимости, но гарантировать, что Rust N153 selector и NativePipeline не изменят переданные данные/порядок. Нельзя выдумывать рыночные знания корабля или менять credit/profit/rounding rules. Отдельные отрицательные A/B на no-funds/stock/fuel/hostile/unknown source и exact BT.

### B6 — station administration roster (только если измерения подтверждают)
После N153 можно брать **другой независимый по файлам** пункт аудита: `godot/scripts/sim/phase2/unified_native_station_administration_phase.gd`. Провести профиль повторных сортировок по facilities/populations/faction/location при неизменной семантике N18. Затем при доказанном горячем пути добавить call-scoped индекс facility/location/faction. Сравнить workforce allocation, production orders, N18 output, деньги и реальный world snapshot. **Проверить свежие leases перед началом**. Не редактировать N39, schema, finance owner, N158 или общий CI. Если дорогое место отсутствует — REJECTED (не нужно изменение).

### B7 — EventQueue (исключительно после профиля)
Файл `godot/scripts/sim/event_queue.gd`. Доказать на реальном tick расписании, что `take_due` повторно сканирует достаточно большой pending, чтобы оправдать bucket/heap. Если выигрыш есть — подобрать deterministic structure с точным исходным порядком событий, отменой, повторными ID, tick boundary, pause/restart. Проверка отдельных fixtures + 420 исходных тиков. При low event count оставить прежний O(N) алгоритм, пометить NO-CHANGE/REJECTED. Не изобретать новую командную систему рядом с N146, не менять N158.

### B8 — переносимые точные fixtures и полноценные gate
Новые тесты `godot/tests/p2_parallel_b_*.gd`: source N153 paid-contract acceptance, `p2_n153_live_contract_dispatch_check.gd`, `p2_n153_route_cache_parity_check.gd`; при найденной проблеме добавить blocked reason/count parity и exact same winner/order/BT/contract/ship fields. Масштаб 24/100/500 с **реально валидными** ship IDs/factions/wallet/fuel/routes/capacity/market/funds/expiration; separate idle/transit scenarios. В конце один пакетный CI: Godot 4.7.2, 420 ticks N38 restart tick360, затем 900 включая tick825, same-host whole-sim A/B и профиль N153. Никаких утверждений о 10k/Windows FPS без фактических измерений.

## Область владения / запреты

**Можно редактировать** `godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd`, новые `godot/scripts/sim/phase2/n153_*index*.gd`, `godot/tests/p2_parallel_b_*.gd`, свои `*parallel-b*.md`; при обязательном свежем lease-check только собственные независимые `godot/scripts/sim/phase2/unified_native_station_administration_phase.gd` и `godot/scripts/sim/event_queue.gd`. Отдельный собственный CI workflow разрешён, без лишних запусков.

**Запрещено** касаться `godot/scripts/sim/phase1/n39_native_world_production.gd`, `godot/scripts/sim/phase1/n39_native_world_schema.gd`, `credit_ledger.gd`, `n158_production_runtime.gd`, `route_graph.gd`, `main.gd`, `p2-unified-godot-smoke.yml`, тестов/документов чата A. Нельзя менять SEARCH_BUDGET, прибыль, AI selector, дипломатический доступ, время тика, ship movement, source Dijkstra. Пересечение → BLOCKED и описание требуемого API, а не правка чужого.

## Как продолжать без новых заданий

1. Прочитать этот файл, общий регламент, текущий lease и свежие обе ветки/PR; затем выбрать первый TODO не заблокированный.
2. Выполнить **реальную разработку и целевые тесты**. Обновить таблицу: TODO → IN_PROGRESS → DONE-TESTED, записать доказательства, SHA и PR. Невыгодное изменение отменить и отметить REJECTED.
3. Не останавливаться после первого исправления, коммита или PASS: переходить к следующему безопасному подблоку в рамках активной итерации. При новом «Продолжай» продолжить из таблицы без повторных вопросов.
4. Группировать близкие изменения внутри одного Draft PR #258; GitHub Actions запускать после набора содержательных блоков, а не на каждую мелочь. Не сливать PR — интеграцию делает координатор.
5. Зеленеть на доске только после PASS + merge. Не дописывать неподтверждённые результаты в чужие карточки. По исчерпании 8 пунктов — зафиксировать ограничения и отдать готовую ветку, не делать фиктивных задач ради занятости.

