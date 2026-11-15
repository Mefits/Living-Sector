# P2 большой блок — N135 -> N104/N9: canonical funded contract posting
13.11.2026. Owner: interactive chat. Branch: `integration/godot-phase2-unified-20261113`, common PR #249.

## Реализовано
- Claims checked and reserved before edits. Production script, schema, projection, N158 tick and observer integrated into **existing N39 World + sole N9 Ledger**, not a second financial subsystem.
- N39 `post_funded_contract(tick, demand)` calls the already existing `unified_contract_escrow_staging.gd` (N135 revalidation, original N104 ContractBoard, one N9 ledger) and commits BOTH world+ledger only after schema, board, wallet conservation, receipt and identity checks.
- `contract_board` and `escrow_balances` are canonical N39 world fields, initialized empty from the frozen Galaxy seed; escrow ledger balances mirror reserved funds exactly. Old checkpoints without both keys are still accepted and can initialize the component on first valid post. Half-present, mismatching or forged escrow state fails validation. N39 restore additionally validates the actual N104 board against the single restored N9 ledger.
- After N150 market phase, N158 now reads real N151 rolling consumption and actual station funds/market supplier stock, then attempts N104 funded contracts for N135 needs. Normal legitimate conflicts are reported in `contract_admissions_snapshot().blocked`; corrupt commit candidates fail the single tick closed. No manual ship UI needed.
- Guard against parallel active orders for same destination+commodity and source quantity over-promise; N135 immutable ID/board refuses replay. No goods magically moved by posting.
- N158 JSON checkpoint restore normalizes N104 contract integer fields, escrow wallets and board version while keeping fractional commodity stock unchanged.
- F5 observer shows active funded N104 contracts, real escrow credits and up to 3 origin->destination contract rows; it explicitly states N153/ship execution is not connected.
- New `godot/tests/p2_live_funded_contract_check.gd` uses real frozen world + controlled N151 receipt fixture to test ONE automatic market tick, paid post, N9 receipt debit/credit conservation, no duplicate posting, true JSON save/reload, and continued autonomous ticking without replay. The fixture creates NO fake market, ship or wallets.

## Verification
Code commits: `dda8e1d6`, `93a8fd30`, `d7560692`, `778a27d5`, `80ed10b1`.
GitHub source readback for all changed scripts PASS: balanced delimiters/strings, zero NULs, no missing preload files. No Godot 4.7.2 runtime available in this session; **test created but not executed**, status **CODE_UNVERIFIED / NOT_ACCEPTED_AS_RUNTIME_PASS**. Zero GitHub Actions runs triggered.

## Known blockers and limitations
- **NOT an autonomous cargo fleet**: N153/N80/N81/N84 decision, N14 dispatch, N21 dock, N15/N97 physical load and N104 payout remain unconnected to this funded contract board. No false "ship completed delivery" claims.
- N135 demand ID is currently stable by destination+commodity+source; N104 refuses reusing an old ID even after closed/expired. Reissuance needs a documented generation/epoch and duplicate-reservation proof before long-term autonomy.
- Supplier stock is guarded at posting against other open N104 orders, but physical reservation/settlement and route feasibility still need atomic integration; source stock can change before pickup.
- On a failed N39/N104 tick, retain old disk checkpoint and use established fail-closed diagnosis; do not continue a partially accepted receipt.

## Next major slice
Connect posted N104 contracts to independent N153 ship eligibility/acceptance and N135 dispatch, then N14/N21/N15/N97 physical pickup/delivery and single-board N104 settlement/refund. One complete unattended route and receipt chain is the minimum next autonomy acceptance, with real Godot parser/smoke/save/load tests before claiming complete.
