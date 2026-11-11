"""Fast unit checks for evidence classification; no Rust/compiler required."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).with_name('ai_runtime_audit.py')
spec = importlib.util.spec_from_file_location('ai_runtime_audit', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TestRuntimeEvidence(unittest.TestCase):
    def test_posted_native_order_is_not_a_paid_delivery(self):
        h = {'factions': [{'faction_id': 'own', 'head': {'htn_execution': {
            'mode': 'native_hybrid_opt_in', 'status': 'submitted',
            'native_order_id': 'c-1', 'plan_id': 'p-1', 'step_id': 's-1'}}}]}
        contracts = {'data': [{'id': 'c-1', 'status': 'posted',
                               'mission_category': mod.NATIVE_TAG, 'requestor_id': 'own'}]}
        seen = {}
        heads, board, steps, terminal = mod.record_view(h, contracts, 'hybrid', seen)
        result = mod.summarise('hybrid', [
            {'tick': 1, 'head_events': heads, 'native_receipts': board, 'ledger_events': steps},
            {'tick': 2, 'head_events': heads, 'native_receipts': board, 'ledger_events': steps},
        ], 'hash', 0, None)
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['native_result_status'], 'inconclusive')
        self.assertEqual(result['native_result'], 'native_delivery_submitted')

    def test_real_paid_native_delivery_is_identified(self):
        strategy = {'factions': [], 'ai_execution': {'active': {'own': {
            'ledger': {'plan_id': 'p1', 'planner_id': 'hybrid_utility_htn_goap_beam',
                       'steps': [{'step': {'step_id': 's1'}, 'phase': 'succeeded',
                                  'native_order_id': 'c1'}]}}}}}
        seen = {}
        heads, board, steps, terminal = mod.record_view(strategy, {'data': [
            {'id': 'c1', 'status': 'paid', 'mission_category': mod.NATIVE_TAG,
             'requestor_id': 'own', 'funding': {'reserved': 0}}]}, 'hybrid', seen)
        result = mod.summarise('hybrid', [
            {'tick': 10, 'head_events': heads, 'native_receipts': board, 'ledger_events': steps},
            {'tick': 12, 'head_events': heads, 'native_receipts': board, 'ledger_events': steps}],
            'hash', 0, None)
        self.assertEqual(result['native_result_status'], 'partial')
        self.assertEqual(result['confirmed_paid_native_contracts'], ['c1'])
        self.assertEqual(result['last_observed_succeeded_ledger_steps'], 1)

    def test_unrelated_paid_contract_does_not_prove_htn(self):
        heads, receipts, steps, terminal = mod.record_view({'factions': []}, {'data': [{
            'id': 'unrelated', 'status': 'paid', 'mission_category': mod.NATIVE_TAG}]},
            'hybrid', {})
        self.assertFalse(receipts)
        summary = mod.summarise('hybrid', [
            {'tick': 1, 'head_events': heads, 'native_receipts': receipts, 'ledger_events': steps},
            {'tick': 3, 'head_events': heads, 'native_receipts': receipts, 'ledger_events': steps},
        ], 'hash', 0, None)
        self.assertEqual(summary['native_result_status'], 'inconclusive')

    def test_legacy_receipts_without_stock_do_not_prove_goal(self):
        outcome = {'faction_id': 'own', 'plan_id': 'p1', 'planner_id': 'hybrid_utility_htn_goap_beam',
                   'final_status': 'completed', 'reason': 'native_htn_goal_completed', 'tick': 100,
                   'steps': [{'step_id': 's1', 'phase': 'succeeded',
                              'native_order_id': 'c1', 'reason_code': 'native_contract_paid'}]}
        summary = mod.summarise('hybrid', [
            {'tick': 90, 'head_events': [], 'native_receipts': [], 'terminal_events': []},
            {'tick': 105, 'head_events': [], 'native_receipts': [], 'terminal_events': [outcome]},
        ], 'hash', 0, None)
        self.assertEqual(summary['native_result_status'], 'inconclusive')
        self.assertEqual(summary['durable_completed_native_plans'], 0)
        self.assertEqual(summary['unverified_legacy_completion_reports'], 1)

    def test_paid_multistep_production_and_goal_stock_is_proof(self):
        outcome = {'faction_id': 'own', 'plan_id': 'p2', 'planner_id': 'hybrid_utility_htn_goap_beam',
                   'final_status': 'completed', 'reason': 'native_receipts_and_goal_stock_confirmed',
                   'tick': 120, 'goal': {'commodity': 'water', 'destination_id': 'port', 'target_units': 10},
                   'observed_goal_stock': 12.0, 'steps': [
                       {'step_id': 's1', 'phase': 'succeeded', 'native_order_id': 'c1',
                        'reason_code': 'native_contract_paid'},
                       {'step_id': 's2', 'phase': 'succeeded', 'native_order_id': 'facility:refinery-1',
                        'reason_code': 'native_recipe_paid_and_step_stock_confirmed'},
                   ]}
        assert mod.confirmed_goal_outcome(outcome)
        assert mod.has_native_recipe_chain(outcome)
        summary = mod.summarise('hybrid', [
            {'tick': 90, 'head_events': [], 'native_receipts': [], 'terminal_events': []},
            {'tick': 130, 'head_events': [{'faction_id':'own','plan_id':'p2','status':'completed'}],
             'native_receipts': [], 'terminal_events': [outcome]},
        ], 'hash', 0, None)
        self.assertEqual(summary['native_result_status'], 'passed')
        self.assertEqual(summary['durable_completed_native_plans'], 1)
        self.assertEqual(summary['confirmed_multistep_recipe_chains'], 1)
        self.assertEqual(summary['completed_native_plan_reports'], 1, 'no double counting head/history')

    def test_real_production_counter_proves_output_even_if_water_was_consumed(self):
        outcome = {'final_status': 'completed',
                   'reason': 'native_recipe_receipts_and_goal_production_confirmed',
                   'goal': {'commodity': 'water', 'target_units': 10},
                   'observed_goal_stock': 0.0, 'produced_goal_units': 10.0,
                   'required_goal_production_units': 10,
                   'steps': [{'phase': 'succeeded', 'native_order_id': 'contract-1',
                              'reason_code': 'native_contract_paid'},
                             {'phase': 'succeeded', 'native_order_id': 'facility:refinery-1',
                              'reason_code': 'native_recipe_paid_and_output_counter_confirmed'}]}
        self.assertTrue(mod.confirmed_goal_outcome(outcome))
        self.assertTrue(mod.has_native_recipe_chain(outcome))
        outcome['produced_goal_units'] = None
        self.assertFalse(mod.confirmed_goal_outcome(outcome))
        outcome['produced_goal_units'] = 10.0
        outcome['steps'][1]['phase'] = 'submitted'
        self.assertFalse(mod.confirmed_goal_outcome(outcome))

    def test_short_stock_or_missing_recipe_receipt_never_proves_chain(self):
        outcome = {'final_status': 'completed', 'reason': 'native_receipts_and_goal_stock_confirmed',
                   'goal': {'target_units': 10}, 'observed_goal_stock': 9.0,
                   'steps': [{'phase': 'succeeded','native_order_id':'facility:refinery',
                              'reason_code':'native_recipe_paid_and_step_stock_confirmed'}]}
        self.assertFalse(mod.confirmed_goal_outcome(outcome))
        outcome['observed_goal_stock'] = 12.0
        self.assertTrue(mod.confirmed_goal_outcome(outcome))
        self.assertFalse(mod.has_native_recipe_chain(outcome), 'no delivery happened')
        outcome['observed_goal_stock'] = float('nan')
        self.assertFalse(mod.confirmed_goal_outcome(outcome))

    def test_stalled_tick_is_failed_technical_run(self):
        summary = mod.summarise('baseline', [
            {'tick': 3}, {'tick': 3}], 'hash', 0, None)
        self.assertEqual(summary['status'], 'failed')


if __name__ == '__main__':
    unittest.main()
