# N143 — макро №8: завершение исходного покрытия системы исследований Rust

**Промежуточный итог: исходная научная механика SOURCE-COVERED в отдельных PR, но CODE_UNVERIFIED, не собрана и не исполнялась в Godot.** Резервация N143 создана заранее в общей ветке (`fea7e986`). Ветка `feature/godot-n143-complete-rust-research-domain-20261112`, основание `integration/godot-47-n33-n37-20261112`. frozen Rust Galaxy 0.6.7 `archive/rust-galaxy-067-reference` неизменен. Никаких T4/1000-летних дополнительных технологий сюда не добавлено.

## Исходный аудит — где каждая часть механики

| Frozen Rust 0.6.7 source | Код уже создан в отдельном PR | Теперь закрывается/стыкуется |
|---|---|---|
| `strategy/director.rs::TECHNOLOGIES`, 12 технологий + prereq/field/work, `has`, `production_bonus` | N82 / [PR #171](https://github.com/Mefits/Living-Sector/pull/171), N44 / [PR #132](https://github.com/Mefits/Living-Sector/pull/132) | N143 принимает авторитетный N82 catalog как аргумент; повторный список технологий НЕ создаёт, бонусы только read-only |
| `strategy/director.rs::observe`, research часть: выбор цели фракцией/mandate, защита уже оплаченного progress, отсутствие дат unlock | N82 cover eligible/choose, N89 / [PR #178](https://github.com/Mefits/Living-Sector/pull/178) partial mandate | **N143 `n143_native_research_director.gd::observe_research`** источниковое переключение целей и синхронизация `research_required`. Не трогает survival, personality/AI и другие ветви наблюдения — те принадлежат макро #7 |
| `strategy/governance.rs::ResearchMandate`, next_technology, set/clear/active, budget inheritance, authorize_research, paid_research | N44 / PR #132, N89 / PR #178 | **N143** различает delegated, advise, hold, completed target, charter research autonomous; в режиме `hold` отказывает до новой оплаты; смена режима на ТУ ЖЕ цель НЕ обнуляет `spent_cr`; новый target — новый бюджет |
| `strategy/charter.rs::FactionCharter::gate/record_paid` для Research | Разрешения и приоритеты относятся также к макро #7; N89 partial charter | **N143** использует только read-only входящий валидный charter и отражает `shared_ceiling_cr`, `protected_treasury_cr`, режим `review` с оплаченной tranche; counters НЕ заменяют основной ledger |
| `strategy/director.rs::research_ready` | N44 readiness только prerequisites, N45 частичная оплачиваемая смена | **N143 `n143_native_research_shift.gd::research_ready`**, source external facts, owner station/electronics/workforce, treasury strict `>` difference |
| `strategy/director.rs::research` full preflight, 1 electronics, salary 10, station cash, one shift/faction/tick, tech completion and history | N45 / [PR #134](https://github.com/Mefits/Living-Sector/pull/134), N76 / [PR #162](https://github.com/Mefits/Living-Sector/pull/162), N120 / [PR #209](https://github.com/Mefits/Living-Sector/pull/209) (but scattered) | **N143** one complete source-order staged paid transaction `prepare_paid_shift`, `verify_authoritative_receipt`, with one atomic external owner. No 2nd debit, no tech grant without real authoritative receipt |
| `strategy/progression.rs` research prerequisites for native T1→T2→T3 station upgrades | N44 and N110 / [PR #198](https://github.com/Mefits/Living-Sector/pull/198) | **Research prereq** is covered. **Actual station upgrade materials + payroll + new station tier** remains macro **#6** and must NOT be labelled 'completed research' here |
| `sim_server/control.rs`, `http/player` mandate endpoints / persistence | Existing server control and save adapters; no standalone Phase-1 source gap in science core | External control interface, player UI, real save/replay and Godot runtime integration are **Phase 2**, separate from completing the scientific **source-domain coverage** |

Это карта **компонентного переноса** по Frozen Rust. Новые файлы N143 не означают, что Н44/45/76/82/89/110/120 уже в одной исполняемой ветке: это несколько **неслитых draft PR**, и единый Godot-мир будет собран во второй фазе. Там проверка/исправление source-parity обязательна.

## Новые N143 файлы

- `godot/scripts/sim/phase1/n143_native_research_director.gd`: выбор исследования, цепочка prerequisites, preservation `paid progress`, один текущий research goal, immutable catalogue input, exact faction paid-mandate + charter preflight and **pure** after-receipt policy projection.
- `godot/scripts/sim/phase1/n143_native_research_shift.gd`: исследование готовности + точная исходная научная смена:
  1. `missing_commander`, `already_researched`, `research_complete`, `survival_first`.
  2. Строгая сортировка рынков по location, проверка через **настоящие** market→facility owner идентификаторы, Electronics stock ≥1 и цена finite 0..10000. При первом подходящем рынке, если treasury < `ceil(price)+10+10000`, Native Rust **сразу** возвращает `research_reserve`, не ищет более дешёвый рынок.
  3. Mandate + charter authorization на **актуальную** стоимость. Уже оплаченные бюджеты revalidated перед любой физической операцией.
  4. Households в этом location/фракции по id; реальная `facility/workforce.rs::occupied_workers(world,tick)` подаётся извне (переиспользовать N141 / [PR #229](https://github.com/Mefits/Living-Sector/pull/229)); свободно `population_count * 3 / 5 - occupied` ≥10.
  5. Проверки переполнения owner facility credits и worker total_wealth, затем ОДНОАТOМНОЕ предложение изменений `-1 Electronics, -cost Treasury, +(cost-10) facility credits, +10 worker wealth`. Сумма кредитов **0**, деньги только перемещаются; Food/industry/mining не участвуют.
  6. Научный прогресс `+10` **только** после оплаченного shift; если `progress >= research_required`, технология добавляется ровно один раз, research Option становится None, история `technology_completed` ограничена 100 записей, `last_research_tick` предотвращает второй платёж в этот же тик. `paid_research` отражает единое фактическое списание в mandate/charter counters, не вторую проводку.
- `godot/scripts/sim/phase1/n143_native_research_domain_checks.gd`: подготовлены source-derived сценарии для режима Hold vs автономной науки, сохранения потраченного, order/location/household tie, прохождения запрета повторов, денег, Electronics и подлинной квитанции. **NOT EXECUTED**.

## Важные тонкости оригинала

**Native ready vs actual research:** `research_ready` требует `treasury > ceil(price)+10010`, а `research()` возвращает `research_reserve` только если `treasury < ceil(price)+10+10000`. На точной границе `research_ready` ложен, но прямое выполнение разрешено. Мы не «выправили» эту исходную асимметрию, чтобы не менять логику Rust. В Phase-2 можно отдельно принять решение исправить её; пока это исходный parity контракт.

**Mandate / charter:** режим `advise` не требует оплату из player directive budget, `hold` запрещает новый research. `research_authority=autonomous` у charter отключает власть player mandates, **не останавливая автономную Genesis науку**. Только реальный attributed delegated shift должен увеличить `mandate.spent_cr` и `charter.spent_research_cr/spent_cr`. Нельзя списывать кредит дважды через N45 и N143; только один реальный ledger owner. N143 `paid_after_receipt` вычисляет предстоящую политику **без side effects**. В Game World нельзя отдельно записать её до фактического paid receipt.

**Atomic boundary:** `Shift.prepare_paid_shift(input, N82.rows)` возвращает proposal, immutable snapshot preconditions and exact `effects`; **не** меняет входные credits/stock/commander. `Shift.verify_authoritative_receipt(proposal, receipt)` — *проверка содержания* trusted receipt, не является доказательством факта банковского списания сама по себе: `authoritative=true` должен проставлять только эксклюзивный native engine transaction manager, никогда UI/сетевой клиент. Результат `commander/mandate/charter` может быть записан лишь в ТОМ ЖЕ подтверждённом authoritative world transaction/checkpoint; иначе возникает опасность частичного гранта/повторной оплаты. При restart authoritative ledger receipts + native Director save должны быть согласованы.

**Source world adapter:** `input` имеет `faction_id,tick,treasury,commander,markets,people,mandate,charter`. Рынки: `id,facility_id,location,owner_faction,facility_type,electronics_supply,electronics_price,facility_credits`; household: `id,faction_id,location,population_count,occupied_workers,wealth` из реальной ECS. Все identity/ownership flags должны быть получены из real ECS и проверены, а не вычислены из названий. N82 catalogue rows are injected, and must contain exactly original 12 technologies before Phase-2 runtime.

**Не переносим здесь:** UI выбора технологии, full Director strategic portfolios, station site upgrade, новых технологий T4/сферу Дайсона, локальные товары и верфи, интерпретацию years. Это собственные области других макро/Фазы 3.

## Честный статус и критерий закрытия

**Покрытие Rust-системы исследований: source-facing contract now documented end-to-end.** Это критерий закрытия **компонентного макро №8 в Фазе 1**, а не утверждение, что уже существует играбельная наука. Все файлы readback и lexical bracket checks; нет Godot parser/headless, нет исполняемого Rust-vs-Godot replay, нет merge в integration/Windows build — статус `CODE_UNVERIFIED`.

Дополнительная оговорка: обнаруженные после source-inventory аудита непокрытые реально существующие Rust science-callers следует оформить новым свободным Nx, а не объявлять непроходимые тесты «фазой 2» без записи. Полное решение будет подтверждено только после интеграции и исполнения в Фазе 2.
