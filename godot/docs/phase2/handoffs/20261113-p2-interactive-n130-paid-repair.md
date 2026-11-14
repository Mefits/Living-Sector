# Living Sector — P2 handoff: N130 реальные сервисные закупки + N156 оплаченный ремонт

**Контекст:** 13.11.2026, единая ветка `integration/godot-phase2-unified-20261113`, PR #249, фаза P2 гейт 1. Это один законченный *интеграционный блок в коде*, не отдельный runtime, не отдельный PR.

## Что внесено

- `991aa0f8`: новый `godot/scripts/sim/phase2/unified_service_restock_phase.gd`, использует оригинальный N130 `facility_restock_n130.gd::plan`. Каждый **20×tick_multiplier** source facilities по стабильному ID берут **только Fuel и Tools**, до порога 100 и цели 500, **из реального market.supply** в **личные `facility.reserves`**. Поставщик = реальный market.owner. Себе — без денежного перевода; другому локальному продавцу — `N9 Ledger.transfer` по действующим ценам и подтверждённый receipt. Для межфракционной торговли до интеграции N150 Relations установлен fail-safe запрет, а не выдуманный дипломатический статус.
- `25482295`: N156 lifecycle читает только принадлежащие станции резервы, принимает **исключительно** подтверждённые оплаченные repair receipts и post-wage cash для решения об abandon; расходует ровно **1 owned Tool** и восстанавливает condition на source +0.01, если condition после decay ниже 0.8 и штат оплачен; без receipt никаких бесплатных ремонтов.
- `858902fe`/`856cb494`: private reserves отражаются в настоящем source seed (пустой `reserves:{ }` не подменяется рыночным запасом) и проверяются общим N39 Inventory/Schema; старый save без reserves допускается как действительно пустой склад.
- `8a0830df` + `1347dff1` + `12cf7afa`: N39 canonical `run_tick` теперь stage → оплаченный N156 `Payroll.pay_shift(producer=owner, cost=0)` через существующий **ОДИН** N9 Ledger → staged N156 source self-repair/abandonment → N130 restock через тот же ledger → Schema/CR balance preflight → единый World/Ledger swap → прежние recipes/mining. Запрещён второй Runner. В обычные тики **не копируется растущий ledger receipts**; в тики с настоящими покупками/ремонтом stages защищают реальные деньги. Никаких выдуманных Tools.
- `3d59d63f`/`fb0b5e24`: N158 live economy summary считает также реальные ремонтные зарплаты и количество покупок; read-only `observer_panel.gd` отображает персональные Fuel/Tools станции, состояние, ремонты, ошибки оплаты и рыночные запасы.
- `3af9b1f7`/`80e8a42f`: локальный тест `godot/tests/p2_n130_service_repair_check.gd` на настоящем Galaxy seed с **только тестовой** повышенной stock и condition=0.75: 20 тиков -> реальные платные закупки, 40 -> самообслуживание после WorkShift, conserved CR, exact ledger receipts, JSON roundtrip native snapshot/restore. Эталонные JSON **не изменены**.

## Важно о проверке

- **WIRED_CODE_UNVERIFIED:** проверены источники на GitHub, согласованность preloads, 8 изменённых GDScript и баланс скобок/круглых/фигурных. Реального Godot executable в среде чата нет; попытка скачать официальный бинарник напрямую упёрлась в недоступный DNS. **Ни локальные Godot проверки, ни GitHub Actions не запускались; успешного нового Windows ZIP нет.**
- Самая полезная следующая проверка **перед новым изменением engine** из полного клона через портативный Godot 4.7.2:
  ```powershell
  & "C:\Tools\Godot_v4.7.2-stable_win64.exe" --headless --path godot --editor --import --quit
  & "C:\Tools\Godot_v4.7.2-stable_win64.exe" --headless --path godot --script res://tests/p2_n130_service_repair_check.gd
  & "C:\Tools\Godot_v4.7.2-stable_win64.exe" --headless --path godot --script res://tests/p2_n158_live_production_check.gd
  ```
  Пример пути подставить реальный. Для визуального теста — GitHub Desktop Pull → Godot F5 → «Наблюдение»; на x8 (tick_multiplier=1) через ~20 тиков увидишь рост private Fuel/Tools и одновременно уменьшение рыночного запаса; **естественный ремонт может случиться значительно позже, когда condition < 0.8**. Тестовый fixture специально задаёт condition=0.75, но не изменяет игру.
- **Требует местной проверки:** GDScript парсер, сравнения сериализованных float, наличие правильных ledger receipts, порядок работников при совпадении repair и recipe на одном тике, реальные 40-тиковые тесты; в случае failure чинить конкретно этот блок, НЕ запускать Actions ради микропатча.
- Существующая SaveState схема остаётся одна (N38/N39), N158 normalization чисел уже обрабатывает ledger/work_shift. Её реальная совместимость с новым полем `reserves` теперь покрыта отдельным тестом, но его надо выполнить.
- Ни старый скачанный Windows artifact #43403286156, ни новый UI после него **не содержат** этих изменений; нужен последующий общий крупный checkpoint.

## Дальнейший гейт

Гейт 1 теперь имеет code-wired N156 condition+crew morale+paid repair и N130 restock, но full closure требует локального smoke, честного отношения к межфракционной торговле, а также dock queue/crew missions при интеграции единого флота. **Следующим самым ценным крупным блоком остаётся Gate 2: 24 исходных корабля в том же World+Clock+Ledger, transit, dock, cargo и save**. Не запускать самостоятельный `live_native_fleet_engine` параллельно с N158, не дублировать market/ledger. Lease `20261113-p2-n130-paid-service-restock-repair-interactive.json` освобождён по окончании.
