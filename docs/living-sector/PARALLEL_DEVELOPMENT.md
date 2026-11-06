# Параллельная разработка: интеграционная база и границы

> **Для нового владельца ядра (Sol):** продолжать от S4 по [HANDOFF.md](HANDOFF.md).
> Указанный ниже SHA S1 остаётся базой независимого Observer, а не последней версией ядра.
> На 2026-11-06 Observer PR #17 (`feature/observer-strategy-ui1`) открыт отдельно,
> HEAD `9450b070d9c818f82850ccd4289130e63a2c69f9`; слияния/совместная проверка с S4 не выполнены.

Дата: 2026-11-06. Текущий блок объединяет завершение строительства, первый
стратегический цикл и интерфейс для второго разработчика. Старые PR не слиты.

## База

Рабочая интеграционная ветка: `integration/genesis-strategy-prototype`, потомок
`feature/genesis-flight-recovery` @ `bb0d24d9f4c898b43df2d35bc75d5dc31855e3cb`.
Это последовательное продолжение существующей цепочки, не merge PR #7–15.
**Проверенная кодовая база: `94af279f54b87ceb732910b0a8574758b60014ee`.**
CI Linux: https://github.com/Mefits/Living-Sector/actions/runs/42134591267 — 15 различных адресных тестов (18 запусков из-за пересечения
фильтров), сборка genesis_server и свежая БД/API smoke прошли. Следующий коммит
обновляет только документацию/пример JSON; код проверенной базы не меняется.
Ветки второго разработчика создавать от закреплённого SHA, не от main/старого UI ZIP:

```sh
git fetch origin integration/genesis-strategy-prototype
git switch -c feature/observer-strategy 94af279f54b87ceb732910b0a8574758b60014ee
```

Новый PR направлять в `integration/genesis-strategy-prototype`. Слияние выполняется
только после отдельного решения владельца, не автоматически. Для запуска свежего
мира задать DATA_DIR=priv/genesis/data и отдельный DATABASE_PATH; режим исполнения
включается LIVING_SECTOR_STRATEGY_MODE=execute, затем cargo run --locked -p sim_server
--bin genesis_server. По умолчанию сервер использует shadow.
Согласование новых изменений API — через владельца ядра; историю не переписывать.

## Правила блока

Одна ветка и один PR на 5–10 связанных задач; промежуточные коммиты допустимы.
Адресные тесты во время работы, интеграционные проверки на контрольных точках.
Повторное исследование — только при новой ошибке, изменении кода или гипотезе.
Некритичные проблемы записываются в backlog. Следующий приоритет — развитие
главы, портфеля целей и администраторов, а не общий аудит экономики.

## Ответственность

| Модуль | Исполнитель | Стабильная граница | Конфликты |
|---|---|---|---|
| ECS, стратегия, native contracts, tick pipeline | основной разработчик | `GET /api/strategy` v1 | не редактировать параллельно sim_core, engine/runtime/snapshot |
| SQLite/checkpoint/migrations | основной разработчик | additive migrations, существующий load_agents | не назначать номера миграций параллельно |
| Панель главы/портфель целей | второй разработчик | JSON API ниже, read-only | `observer/app.js`, styles, index — только одна UI-ветка за раз |
| Карточки проектов/администратора | второй разработчик | `projects[].contract_id`, `executor_id` + старые API | не выдумывать отсутствующие статусы/новые команды |
| Timeline диагностики | второй разработчик | опрос snapshot_tick, локальный diff; не обещать event log | потеря промежуточных состояний между опросами допустима и видима |
| Независимая проверка схемы/fixtures | второй разработчик | отдельные `tools/strategy-diagnostics/`, `tests/strategy-api/` | не менять Rust-тесты/общий CI без согласования |
| Альтернативный scorer целей | второй разработчик, только pure prototype | вход `goals[]`, выход упорядоченные goal_id/commodity/destination | не подключать к runtime и не списывать бюджет самостоятельно |

Основной разработчик в этом блоке **не реализует Observer-панель**. Можно
параллельно делать UI и инструмент диагностики в непересекающихся каталогах.
Сначала отдельный прототип scorer, затем согласованное подключение; внутренние
Rust-типы стратегии пока не являются обещанием стабильного плагин-ABI.

Файлы, которые пока нельзя менять параллельно: `crates/sim_core/**`,
`crates/sim_db/**`, `crates/sim_server/src/engine/**`, `engine.rs`, `runtime.rs`,
`snapshot.rs`, `http/api.rs`, `.github/workflows/genesis-economic-checkpoint.yml`.
Также владелец ядра обновляет STATUS/ASTRA_START_HERE; UI-разработчик ведёт
свой `docs/living-sector/OBSERVER_STRATEGY_NOTES.md`.

## API v1 (реализован)

`GET /api/strategy` — один JSON-объект, не `{data: ...}`; только чтение.
Корень: `schema_version:1`, `snapshot_tick:u64`, `mode:"shadow"|"execute"`,
`factions:[]`, порядок faction_id стабильный.

Каждая фракция: `faction_id`, `observed_tick` (возраст наблюдения отдельно от
snapshot_tick), `treasury`, `goals:[]`, `selected_goal:Goal|null`,
`administrator:"logistics"`, `status`, `reason`, `projects:[]`.
Goal: `goal_id`, `commodity`, `destination`, `shortage_ticks`, `score`.
Ключ строки Goal — тройка (goal_id, commodity, destination), goal_id обозначает
категорию, не уникальный экземпляр. Текущие goal_id: sustain_population / secure_fuel / supply_industry.
Это портфель ранжированных дефицитов, не вся будущая стратегическая модель.

Статусы решения: observing / idle / proposed / blocked / waiting / commissioned.
Причины: awaiting_cycle / no_chronic_shortage / shadow_no_mutation /
no_accessible_stock / insufficient_budget / existing_contract / funded_native_contract.
Неизвестные будущие значения UI показывает текстом, не ломает рендер.

Project: `project_id` (совпадает с contract_id), `contract_id`, `administrator`,
`state` (posted/accepted/picked_up/delivered/paid/expired), `executor_id:string|null`,
`reserved_credits`, `source`, `destination`, `commodity`, `quantity`.
В диагностике максимум 32 последних проекта; это не полный журнал.
status/reason фракции описывают последнее решение, не текущий итог всех проектов;
актуальное исполнение смотреть в projects[].state. Пример формы ответа:
[strategy-api-v1.example.json](strategy-api-v1.example.json) — синтетический UI fixture,
не результат настоящей игровой сессии. Новые поля v1 добавляются совместимо;
переименование/смена смысла требует новой schema_version и согласования.
Смысл quantity — реальные единицы native cargo; кредиты — целые числа.
Между обновлениями не сравнивать Entity handles: API их не выдаёт.

## Что уже исполняется

По умолчанию shadow: глава предлагает, стратегический слой не тратит денег.
Старые native процессы экономики продолжают работать — shadow не ставит мир на паузу.
`LIVING_SECTOR_STRATEGY_MODE=execute` перед запуском включает первый проект:
голова ранжирует хронические дефициты принадлежащих фракции узлов; администратор
логистики выбирает доступный источник, проверяет казну и создаёт обеспеченный
subsidy-контракт. Только выбор subsidy заменяется стратегией; налоги, строительство,
планировщики кораблей остаются штатными. Не более одного активного стратегического
проекта на фракцию; дубликат destination/commodity любого контракта блокирует новый.
В прототипе партия 200, базовая оплата 1600, неснижаемый остаток казны 5000.

Статус проекта выводится из настоящей доски; marker `mission_category=strategy.logistics.v1`
сохраняется существующим checkpoint. После загрузки связь с проектом восстанавливается,
новый проект не создаётся поверх удерживаемого. Бюджет резервируется native escrow;
товар поставщика заранее НЕ резервируется, Buy повторно проверяет физический stock.
Первый исполнитель — существующий автономный корабль. Реализован один администратор,
логистический; другие администраторы остаются следующими расширениями.

## Совместимость и отложенные проблемы

Migration 016 добавляет nullable origin стройки и unique index, не меняет старые строки.
Построенные объекты используют отрицательные стабильные DB-id; seed/admin IDs положительные.
Сейвы обновляются только вперёд: старую программу нельзя направлять на уже обновлённую БД.
Проверку проводить на копии существующего сейва или отдельной новой БД; оригиналы не удалять.

Прямые admin/respawn INSERT, полный RNG/BT/crew replay, физическая курьерская погрузка,
обобщённый ReservationBook и долгий баланс отложены. Возвращаться к ним только при
конкретном блокировании ближайшего стратегического сценария. UI 0.14 из ZIP не
подмешивается в проверенную базу автоматически.

## S2: совместимое расширение в отдельной ветке

`feature/genesis-strategy-replanning` основана на S1; закреплённая база второго
разработчика **не меняется** до согласованного слияния. API остаётся v1, прежние
поля сохранены. Добавлено необязательное для старого UI поле `assessments`:
массив `{goal: Goal, reason: string, source: string|null}` в порядке `goals`.
Причины: ready / existing_contract / no_accessible_stock / insufficient_budget.
`ready` означает доступность для выбора, а не выданное задание: один уже
удерживаемый стратегический проект запрещает запуск второго. Все оценки —
наблюдение на observed_tick, не гарантия будущего stock и не резерв товара.

Глава выбирает первую выполнимую цель ранжированного портфеля. При удерживаемом
проекте selected_goal продолжает указывать его цель, даже если дефицит исчез:
в этом случае shortage_ticks=0 и score=0, а цели может не быть в goals[].
Delivered ожидает расчёта; Paid/Expired с ненулевым escrow ожидает завершения
native settlement/refund. Стратегия сама не возвращает деньги и не меняет статус
контрактов. После освобождения проекта следующий цикл заново оценивает потребности.
В projects[] сначала идут незавершённые/нерассчитанные проекты, затем история;
лимит 32 сохранён. UI не должен считать первый элемент самым новым по времени.

Сохранения и миграции в S2 не меняются. Повторное создание StrategyState восстанавливает
удерживаемую цель из native contracts. Полная история решений по-прежнему не сохраняется.

## S3: строительный администратор (совместимое расширение v1)

Ветка `feature/genesis-strategy-construction`, PR #19 поверх S2. Для независимой
UI-ветки по-прежнему использовать закреплённый S1 SHA выше, до согласованной интеграции.
Старые поля фракции selected_goal/status/reason/administrator описывают логистику.
Новое поле `construction` равно null до первого строительного цикла, затем объект:

- observed_tick: возраст решения, status/reason: последнее решение администратора;
- selected_goal: Goal с goal_id=expand_production либо null;
- site_id: текущая площадка либо null; facility_type: планируемый/сохранённый тип;
- progress_delivered/progress_required: текущая площадка, 0/0 при её отсутствии;
- contract_id: удерживаемая/последняя выданная поставка либо null.

Причины: no_chronic_shortage, existing_contract, site_owned_by_other_faction,
no_producer, producer_already_present, invalid_site_location, no_local_resource,
awaiting_materialization, no_accessible_stock, insufficient_budget,
shadow_no_mutation, funded_native_contract. Статусы прежние: idle/blocked/waiting/
proposed/commissioned. Прогресс обновляется между решениями. null site_id сам по себе
не доказывает завершение: это также ещё не созданная/удалённая площадка.

projects[] теперь содержит также administrator=construction с прежней формой Project;
marker native-контракта strategy.construction.v1. Это список поставок, а не один
агрегированный проект здания; завершение paid одной поставки не означает готовность
объекта. Логистические строки/поля не переименованы. UI должен поддерживать новые
значения administrator и отдельную карточку construction, не менять серверные типы.
После загрузки сохранённая стройка возобновляется на следующем строительном цикле.

## S4: общий выбор главы и бюджет текущего цикла

Ветка `feature/genesis-strategy-coordination` поверх S3. Закреплённая база S1
для второго разработчика остаётся неизменной; UI-файлы не изменены.
В API v1 добавлено поле фракции `head: null | HeadDecision`:

- observed_tick, selected_administrator (logistics/construction/null), reason;
- treasury_before: единый баланс до исполнения предложений;
- spending_limit: max(treasury_before - 5000, 0), не отдельный счёт/резерв;
- planned_spend: сумма выбранной новой поставки (1600/10000/0);
- committed_spend: фактический escrow стратегических контрактов, созданных в этом тике;
- proposals[]: administrator, goal (Goal|null), status, reason, requested_credits, priority.

Предложения фиксируются ДО исполнения, поэтому status=proposed в proposals[] не
означает, что оба выполнены. Фактический результат смотреть в прежних полях
логистики/construction и projects[]. Поля head описывают последний цикл, не баланс
на текущем snapshot_tick. Существующий UI может игнорировать head.

Причины главы: urgent_supply / finish_existing_construction / expand_production /
supply_industry / no_feasible_proposal / already_commissioned_this_tick.
Готовый, но не выбранный администратор получает waiting/head_priority.

Прототип политики: 3 — выполнимое снабжение Food/Water/Fuel; 2 — продолжение своей
площадки; 1 — новое производство; 0 — обычная логистика. Внутри уровня выше score,
при равенстве стабильный порядок administrator. Это текущая политика прототипа,
не окончательный игровой баланс. Статусы blocked/waiting не участвуют в выборе.

Оба стратегических администратора оцениваются вместе каждые 60 * tick_multiplier
тиков, не более одного НОВОГО оплаченного контракта фракции за цикл. Уже начатые
контракты продолжают исполняться одновременно. Порог строительной казны 30000
сохранён; общая нижняя граница 5000 дополнительно ограничивает выбор главы.
В shadow предложения/выбор записываются, но committed_spend=0; legacy экономика
продолжается, её строительная частота остаётся 200 * tick_multiplier.

Повторный вызов в одном тике блокируется transient-маркером, после пересоздания
StrategyState — persisted native-контрактом с тем же posted_at_tick. Это не полное
восстановление истории решений. Нет нового ledger, миграций, резервирования всех
будущих этапов строительства или автоматического перераспределения старого escrow.
