"""Check the initial native data, not simulated runtime results."""
import json
from pathlib import Path
import tempfile
import unittest
import importlib.util

path=Path(__file__).with_name('make_ai_water_chain_fixture.py')
spec=importlib.util.spec_from_file_location('make_ai_water_chain_fixture',path)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ROOT=path.parents[1]


class NativeFixtureTest(unittest.TestCase):
    def test_scenario_is_copied_without_touching_original(self):
        original=ROOT/'priv/galaxy/data'
        sol=original/'worlds/sol.json'
        before=sol.read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            destination=Path(tmp)/'fixture'
            report=module.create_fixture(original,destination)
            data=json.loads((destination/'worlds/sol.json').read_text(encoding='utf-8'))
            earth=next(m for m in data['markets'] if m['facility_id']=='earth-station')
            ice=next(m for m in data['markets'] if m['facility_id']=='mine-near-earth')
            self.assertEqual((earth['supply']['water'],earth['supply']['ice']),(0,0))
            self.assertEqual(ice['supply']['ice'],600)
            self.assertTrue(any(f['type']=='refinery' and f['location']=='earth-station'
                                for f in data['facilities']))
            self.assertTrue(any(s['location']=='mine-near-earth' and s['class']=='freighter'
                                for s in data['ships']))
            self.assertEqual(report['kind'],'native_water_chain_initial_state')
            with self.assertRaises(FileExistsError):
                module.create_fixture(original,destination)
        self.assertEqual(sol.read_bytes(),before)


if __name__=='__main__': unittest.main()
