"""Check that simulator failure or incomplete host evidence cannot become a pass."""

import json
import unittest

from run_core import checked_results


class ProbeResultTests(unittest.TestCase):
    def test_matrix_requires_every_scenario(self):
        result = {
            "test": "matrix_cpu_to_rtl",
            "pass": True,
            "valid_commands": 8,
            "rejected_commands": 15,
            "checked_elements": 401,
            "active_resets": 1,
            "completion_stall_cycles": 1,
            "command_cycles": 1,
        }
        self.assertTrue(checked_results(json.dumps(result), "matrix_probe", False, 0)[1])
        for key in result:
            with self.subTest(missing=key):
                incomplete = {k: v for k, v in result.items() if k != key}
                self.assertFalse(
                    checked_results(json.dumps(incomplete), "matrix_probe", False, 0)[1]
                )
        self.assertFalse(checked_results(json.dumps(result), "matrix_probe", False, 3)[1])

    def test_complete_core_result(self):
        text = json.dumps({"pass": True, "commands": [{}] * 6, "doorbells": 6, "completions": 6})
        self.assertTrue(checked_results(text, "core_probe", False, 0)[1])
        self.assertFalse(checked_results(text, "core_probe", False, 3)[1])

    def test_missing_completion_is_failure(self):
        text = json.dumps({"pass": True, "commands": [{}] * 6, "doorbells": 6, "completions": 5})
        self.assertFalse(checked_results(text, "core_probe", False, 0)[1])

    def test_missing_or_truncated_result_is_failure(self):
        for text in ("", "VCS finished", '{"pass":'):
            self.assertFalse(checked_results(text, "llama_probe", False, 0)[1])

    def test_model_check_requires_both_results(self):
        text = json.dumps({"pass": True})
        self.assertFalse(checked_results(text, "llama_probe", True, 0)[1])
        self.assertTrue(checked_results(text + "\n" + text, "llama_probe", True, 0)[1])

    def test_simulator_error_overrides_pass(self):
        for error in (
            "Error-[TEST] deliberate error",
            "Fatal: deliberate",
            "Assertion check failed",
        ):
            text = error + '\n{"pass":true}'
            self.assertFalse(checked_results(text, "llama_probe", False, 0)[1])


if __name__ == "__main__":
    unittest.main()
