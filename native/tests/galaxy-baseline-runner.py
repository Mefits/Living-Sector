#!/usr/bin/env python3
"""Read-only acceptance snapshot for a *real* Galaxy server binary.

Does not compile Rust, simulate decisions in Python, or modify a user save.
The supplied executable and scenario are hashed; each run gets a fresh SQLite
path. Start mode is fixed to the real 3-faction Galaxy game.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import sqlite3
from pathlib import Path
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROUTES = (
    '/api/health', '/api/strategy', '/api/report', '/api/markets',
    '/api/contracts', '/api/facilities', '/api/populations', '/api/ships',
)


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def fetch(base, route, timeout=3):
    with urllib.request.urlopen(base + route, timeout=timeout) as response:
        if response.status != 200:
            raise RuntimeError(f'{route} returned HTTP {response.status}')
        return json.loads(response.read())


def item_count(value):
    if isinstance(value, dict):
        for key in ('data', 'factions'):
            if isinstance(value.get(key), list):
                return len(value[key])
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument('--out', type=Path, required=True, help='New or existing output folder; database must not exist')
    ap.add_argument('--port', type=int, default=18085)
    ap.add_argument('--seconds', type=float, default=8.0, help='Sampling period after startup')
    ap.add_argument('--startup-timeout', type=float, default=15.0)
    args = ap.parse_args()
    project = args.project.resolve()
    binary = project / 'genesis-server-linux'
    data = project / 'priv/galaxy/data'
    out = args.out.resolve()
    db = out / 'galaxy-test.db'
    if not binary.is_file() or not data.is_dir():
        ap.error('Missing Linux server or priv/galaxy/data')
    if db.exists():
        ap.error(f'Refusing to overwrite an existing game database: {db}')
    out.mkdir(parents=True, exist_ok=True)
    base = f'http://127.0.0.1:{args.port}'
    env = {**os.environ, 'BIND_ADDR': f'127.0.0.1:{args.port}',
           'DATABASE_PATH': str(db), 'DATA_DIR': str(data),
           'LIVING_SECTOR_UI_DIR': str(project / 'observer'),
           'LIVING_SECTOR_GALAXY': '1', 'LIVING_SECTOR_STRATEGY_MODE': 'execute',
           'WORLD_SPEED': '16'}
    metadata = {
        'schema_version': 1,
        'timestamp_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'purpose': 'galaxy_0_2_existing_binary_baseline',
        'binary': str(binary), 'binary_sha256': digest(binary),
        'cargo_lock_sha256': digest(project / 'Cargo.lock'),
        'scenario_files': {str(p.relative_to(project)): digest(p) for p in sorted(data.rglob('*.json'))},
        'seconds': args.seconds, 'port': args.port,
        'new_rust_code_tested': False,
        'rng_state_reproducible': False,
        'checks': {}, 'errors': [],
    }
    proc = None
    stdout_path, stderr_path = out / 'server.stdout.log', out / 'server.stderr.log'
    with stdout_path.open('w') as stdout, stderr_path.open('w') as stderr:
        try:
            proc = subprocess.Popen([str(binary)], cwd=project, env=env,
                                    stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                    start_new_session=True)
            deadline = time.monotonic() + args.startup_timeout
            health = None
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise RuntimeError(f'Server exited during startup: {proc.returncode}')
                try:
                    health = fetch(base, '/api/health', timeout=1)
                    break
                except (OSError, ValueError, RuntimeError):
                    time.sleep(0.25)
            if health is None:
                raise RuntimeError('Server did not become healthy before startup timeout')
            first_tick = health.get('tick')
            metadata['first_tick'] = first_tick
            metadata['checks']['health_status'] = health.get('status') == 'ok'
            time.sleep(max(0, args.seconds))
            snapshots = {}
            for route in ROUTES:
                try:
                    snapshots[route] = fetch(base, route)
                    metadata['checks'][f'endpoint_{route}'] = True
                except (OSError, ValueError, RuntimeError) as exc:
                    metadata['checks'][f'endpoint_{route}'] = False
                    metadata['errors'].append(f'{route}: {exc}')
            (out / 'snapshots.json').write_text(json.dumps(snapshots, ensure_ascii=False, indent=2), encoding='utf-8')
            last = snapshots.get('/api/health', {})
            report = snapshots.get('/api/report', {})
            strategy = snapshots.get('/api/strategy', {})
            last_tick = last.get('tick')
            metadata['last_tick'] = last_tick
            metadata['checks']['tick_advanced'] = isinstance(first_tick, int) and isinstance(last_tick, int) and last_tick > first_tick
            metadata['checks']['execute_mode'] = strategy.get('mode') == 'execute'
            metadata['checks']['three_factions'] = len(strategy.get('factions', [])) == 3
            metadata['checks']['world_in_report'] = len(report.get('systems', [])) > 0
            metadata['checks']['sqlite_created'] = db.is_file() and db.stat().st_size > 0
            metadata['endpoint_counts'] = {route: item_count(value) for route, value in snapshots.items()}
            metadata['faction_ids'] = sorted(f.get('faction_id', '') for f in strategy.get('factions', []))
            metadata['report_tick'] = report.get('tick')
            metadata['world_seed'] = last.get('world_seed')
        except Exception as exc:
            metadata['errors'].append(f'{type(exc).__name__}: {exc}')
        finally:
            if proc is not None:
                if proc.poll() is None:
                    # Target the process itself, not the entire interactive session.
                    proc.send_signal(signal.SIGTERM)
                    try:
                        proc.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=5)
                        metadata['errors'].append('Server did not terminate gracefully after SIGTERM')
                metadata['server_exit_code'] = proc.returncode
                metadata['server_terminated_by_sigterm'] = proc.returncode == -signal.SIGTERM
            metadata['checks']['sqlite_created_after_exit'] = db.is_file() and db.stat().st_size > 0
            if db.is_file():
                try:
                    with sqlite3.connect(f'file:{db}?mode=ro', uri=True, timeout=3) as database:
                        result = database.execute('PRAGMA integrity_check').fetchone()
                        metadata['sqlite_integrity_check'] = result[0] if result else None
                        metadata['checks']['sqlite_integrity'] = bool(result and result[0] == 'ok')
                        metadata['sqlite_tables'] = [row[0] for row in database.execute(
                            'SELECT name FROM sqlite_master WHERE type=\'table\' ORDER BY name')]
                except sqlite3.Error as exc:
                    metadata['checks']['sqlite_integrity'] = False
                    metadata['errors'].append(f'SQLite integrity check: {exc}')
    metadata['status'] = 'passed' if metadata['checks'] and all(metadata['checks'].values()) and not metadata['errors'] else 'failed'
    (out / 'summary.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f"Baseline {metadata['status']}: {metadata.get('first_tick')} → {metadata.get('last_tick')} ticks; "
          f"3 factions={metadata['checks'].get('three_factions')}; outputs={out}")
    if metadata['errors']:
        print('\n'.join(metadata['errors']), file=sys.stderr)
    return 0 if metadata['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
