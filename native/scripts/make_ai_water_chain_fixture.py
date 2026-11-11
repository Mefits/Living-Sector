#!/usr/bin/env python3
"""Prepare a controlled *starting situation* for a real Genesis AI check.

All changes occur BEFORE the game starts, on an isolated COPY of the normal
Galaxy seed. No simulated orders, money, delivery, or recipe output is injected
at runtime. The unmodified main Galaxy scenario is never overwritten.
"""
import argparse
import json
from pathlib import Path
import shutil


def create_fixture(source: Path, dest: Path) -> dict:
    if dest.exists():
        raise FileExistsError(f"Refusing to overwrite existing fixture: {dest}")
    if not (source / 'worlds' / 'sol.json').is_file():
        raise FileNotFoundError('Expected native Galaxy sol.json')
    dest.mkdir(parents=True)
    try:
        shutil.copytree(source, dest, dirs_exist_ok=True)
        file = dest / 'worlds' / 'sol.json'
        world = json.loads(file.read_text(encoding='utf-8'))
        stations = [f for f in world['facilities'] if f.get('location') == 'earth-station'
                    and f.get('type') == 'station' and f.get('faction_id') == 'terran-authority']
        refinery = [f for f in world['facilities'] if f.get('location') == 'earth-station'
                    and f.get('type') == 'refinery' and f.get('faction_id') == 'terran-authority']
        target = [m for m in world['markets'] if m.get('facility_id') == 'earth-station']
        assert len(stations) == len(refinery) == len(target) == 1, 'Unexpected native producer/station schema'
        assert any(r['from'] == 'earth-station' and r['to'] == 'mine-near-earth'
                   or r['to'] == 'earth-station' and r['from'] == 'mine-near-earth'
                   for r in world['travel_routes']), 'Expected native local route'
        assert any(b['id'] == 'near-earth' for b in world['bodies'])
        if any(f.get('location') == 'mine-near-earth' for f in world['facilities']):
            raise ValueError('Near-Earth test location already contains facilities')
        # The target has food and credit reserves, but needs an actual ice supply.
        # Disallow local ice extraction on Earth for this *one controlled start*.
        target[0]['supply']['ice'] = 0
        target[0]['supply']['water'] = 0
        target[0]['demand']['water'] = max(8, target[0]['demand'].get('water', 0))
        for body in world['bodies']:
            if body['id'] == 'earth':
                body['resources']['ice'] = 0
        world['facilities'].append({
            'id': 'facility-ai-ice-depot', 'name': 'AI test: Near-Earth ice depot',
            'faction_id': 'terran-authority', 'location': 'mine-near-earth',
            'body': 'near-earth', 'type': 'station', 'docking_capacity': 8,
            'services': ['market', 'repair', 'refuel'], 'reserves': {}, 'credits': 60000,
        })
        world['markets'].append({
            'id': 'market-ai-ice-depot', 'facility_id': 'mine-near-earth',
            'price_elasticity': 0.02,
            'prices': {'ice': 10, 'water': 12, 'food': 18, 'fuel': 25},
            'supply': {'ice': 600, 'food': 200, 'fuel': 200},
            'demand': {'ice': 0, 'water': 0}, 'production': {}, 'consumption': {},
        })
        world['ships'].append({
            'name': 'AI test: near-earth ice freighter', 'location': 'mine-near-earth',
            'class': 'freighter', 'credits': 40000, 'faction_id': 'terran-authority',
            'fitting': {'comms': 'comms_t2'},
        })
        file.write_text(json.dumps(world, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        report = {'kind': 'native_water_chain_initial_state',
                  'input': str(source.resolve()), 'data_dir': str(dest.resolve()),
                  'faction': 'terran-authority', 'target_location': 'earth-station',
                  'source_location': 'mine-near-earth', 'commodity': 'water',
                  'input_commodity': 'ice',
                  'start_stock_target_water': 0, 'start_stock_target_ice': 0,
                  'start_stock_source_ice': 600,
                  'qualification': 'Initial condition ONLY. Not an AI execution result.'}
        (dest / 'AI-FIXTURE-START.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        return report
    except Exception:
        shutil.rmtree(dest)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1] / 'priv/galaxy/data')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(create_fixture(args.source, args.output), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
