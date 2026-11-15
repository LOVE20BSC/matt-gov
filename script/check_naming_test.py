import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import check_naming


class NamingTest(unittest.TestCase):
    def violations(self, source):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "Queries.sol"
            path.write_text(source)
            with patch.object(check_naming, "ROOT", root):
                return check_naming.check([check_naming.File(path, "core")])

    def test_by_key_accepts_parameter_struct_fields(self):
        self.assertEqual(self.violations("""
            struct GlobalPage { uint256 round; }
            library Queries {
                struct Page { uint256 requestedRound; }
                function entriesByRound(Page memory page) external {}
                function globalEntriesByRound(GlobalPage memory page) external {}
                function qualifiedEntriesByRound(Queries.Page memory page) external {}
                function directEntriesByRound(uint256 round) external {}
            }
        """), [])

    def test_by_key_rejects_unrelated_struct_fields(self):
        violations = self.violations("""
            struct Page { uint256 round; }
            library Other {
                struct Filter { uint256 round; }
            }
            library Queries {
                struct Page { uint256 offset; }
                struct Filter { uint256 limit; }
                function entriesByRound(Page memory page) external {}
                function filteredEntriesByRound(Filter memory filter) external {}
                function qualifiedEntriesByRound(Other.Filter memory filter) external {}
                function entriesBySenderId(uint256 targetSenderId) external {}
            }
        """)
        self.assertEqual(
            {(v["rule"], v["symbol"]) for v in violations},
            {("N05", "entriesByRound"), ("N05", "filteredEntriesByRound"), ("N05", "entriesBySenderId")},
        )


if __name__ == "__main__":
    unittest.main()
