"""Compare real saved-state replay windows; fail on any per-tick divergence."""
import json
import pathlib
import statistics
import sys
folder = pathlib.Path(sys.argv[1])
rows = []
for before_path in sorted(folder.glob('ls-replay-legacy-*.json')):
    tick = int(before_path.stem.rsplit('-', 1)[1])
    after_path = folder / f'ls-replay-owned-{tick}.json'
    before, after = (json.loads(p.read_text()) for p in (before_path, after_path))
    assert before['trace'] == after['trace'], f'per-tick state mismatch at {tick}'
    assert len(before['trace']) == 32
    assert before['digest'] == after['digest']
    assert before['tick'] == after['tick'] == tick + 32
    b, a = (statistics.mean(x['costs_us']) / 1000 for x in (before, after))
    row = dict(start=tick, end=tick+32, legacy_ms=b, owned_ms=a,
               speedup=b/a, reduction_percent=(1-a/b)*100,
               all_32_states_identical=True, digest=before['digest'],
               legacy_ledger=before['ledger'], owned_ledger=after['ledger'])
    rows.append(row)
assert rows, 'no paired replay windows'
(folder/'comparison.json').write_text(json.dumps(rows, indent=2)+'\n')
print(json.dumps(rows, indent=2))
