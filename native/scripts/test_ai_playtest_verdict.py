import unittest
from ai_playtest_verdict import evaluate


class RealNativeProofTests(unittest.TestCase):
    def test_only_a_complete_paid_delivery_and_recipe_counts_as_proven(self):
        result = {'results': [{'mode': 'hybrid', 'status': 'passed',
                   'confirmed_multistep_recipe_chains': 1,
                   'confirmed_terran_earth_water_chains': 1}]}
        self.assertEqual(evaluate(result)[0], 'PROVEN')

    def test_unrelated_valid_chain_does_not_prove_earth_water(self):
        result = {'results': [{'mode': 'hybrid', 'status': 'passed',
                   'confirmed_multistep_recipe_chains': 2,
                   'confirmed_terran_earth_water_chains': 0}]}
        self.assertEqual(evaluate(result)[0], 'PARTIAL')

    def test_paid_shipping_alone_is_partial(self):
        self.assertEqual(evaluate({'results': [{'mode': 'hybrid', 'status': 'passed',
                         'confirmed_paid_native_contracts': ['abc']}]})[0], 'PARTIAL')

    def test_healthy_http_is_not_hybrid_success(self):
        self.assertEqual(evaluate({'results': [{'mode': 'hybrid', 'status': 'passed'}]})[0], 'INCONCLUSIVE')

    def test_dead_server_is_error(self):
        self.assertEqual(evaluate({'results': [{'mode': 'hybrid', 'status': 'failed'}]})[0], 'ERROR')

    def test_baseline_result_cannot_prove_hybrid(self):
        self.assertEqual(evaluate({'results': [{'mode': 'baseline', 'status': 'passed',
                         'confirmed_multistep_recipe_chains': 1}]})[0], 'ERROR')


if __name__ == '__main__':
    unittest.main()
