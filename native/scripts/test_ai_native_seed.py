#!/usr/bin/env python3
"""Check the actual Galaxy seed's station-market/module ownership pattern.

This is a source-fixture check, NOT a proof that the new Rust AI is running.
It guards against returning to the incorrect 'market == producer' assumption.
"""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class NativeGalaxySeedContract(unittest.TestCase):
    def test_real_galaxy_has_station_market_and_distinct_colocated_refinery(self):
        found=[]
        for file in (ROOT / 'priv/galaxy/data/worlds').glob('*.json'):
            world=json.loads(file.read_text(encoding='utf-8'))
            facilities=world.get('facilities',[])
            markets=world.get('markets',[])
            for station in (f for f in facilities if f.get('type')=='station'):
                loc=station.get('location')
                modules=[f for f in facilities if f.get('location')==loc and f.get('type')=='refinery']
                if modules and any(m.get('facility_id')==loc for m in markets):
                    self.assertTrue(all(f.get('id')!=station.get('id') for f in modules))
                    found.append((file.name,loc))
        self.assertTrue(found,'Expected native station-market plus separate refinery; the AI fixture assumption changed')
        print('Observed real native market/module pattern:',found)

    def test_original_world_source_is_not_overwritten(self):
        galaxy=ROOT/'priv/galaxy/data/worlds/sol.json'
        genesis=ROOT/'priv/genesis/data/worlds/sol.json'
        self.assertTrue(galaxy.is_file() and genesis.is_file())
        # The research uses a copy of existing game seed data, not runtime gifts.
        self.assertTrue(json.loads(galaxy.read_text(encoding='utf-8')).get('facilities'))
        self.assertTrue(json.loads(genesis.read_text(encoding='utf-8')).get('facilities'))

if __name__=='__main__': unittest.main()
