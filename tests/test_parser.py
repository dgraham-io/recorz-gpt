from __future__ import annotations

import json
import unittest
from pathlib import Path

import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from recorz.parser import ParseError, parse, parse_file


class ParserTests(unittest.TestCase):
    def test_code_example_matches_fixture(self) -> None:
        program = parse_file(str(REPO_ROOT / "docs" / "code_example.md"))
        fixture_path = REPO_ROOT / "docs" / "fixtures" / "code_example.ast.json"
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        self.assertEqual(program.to_dict(), fixture)

    def test_rejects_reserved_block_argument(self) -> None:
        with self.assertRaises(ParseError):
            parse("[ :self | self ]")

    def test_parses_cascade(self) -> None:
        program = parse("p x: 3; y: 4.")
        body = program.body
        assert body is not None
        stmt = body.statements[0]
        node = stmt.expression
        self.assertEqual(node.__class__.__name__, "Cascade")
        self.assertEqual(len(node.chains), 2)
        self.assertEqual(node.chains[0][0].selector, "x:")
        self.assertEqual(node.chains[1][0].selector, "y:")

    def test_parses_nested_object_array_literal(self) -> None:
        program = parse("arr := #(#(1 2) #foo true 'ok').")
        body = program.body
        assert body is not None
        stmt = body.statements[0]
        self.assertEqual(stmt.assignments, ["arr"])
        arr = stmt.expression
        self.assertEqual(arr.__class__.__name__, "ObjectArrayLiteral")
        self.assertEqual(arr.elements[0].__class__.__name__, "ObjectArrayLiteral")
        self.assertEqual(arr.elements[0].elements[0].text, "1")
        self.assertEqual(arr.elements[0].elements[1].text, "2")
        self.assertEqual(arr.elements[1].value, "foo")
        self.assertEqual(arr.elements[2].value, "true")
        self.assertEqual(arr.elements[3].value, "ok")

    def test_parses_radix_scaled_and_float_literals(self) -> None:
        program = parse("a := 16rFF. b := -12.34s5. c := 1e+3.")
        body = program.body
        assert body is not None
        self.assertEqual(body.statements[0].expression.__class__.__name__, "IntegerLiteral")
        self.assertEqual(body.statements[0].expression.text, "16rFF")
        self.assertEqual(body.statements[1].expression.__class__.__name__, "ScaledDecimalLiteral")
        self.assertEqual(body.statements[1].expression.text, "-12.34s5")
        self.assertEqual(body.statements[2].expression.__class__.__name__, "FloatingPointLiteral")
        self.assertEqual(body.statements[2].expression.text, "1e+3")

    def test_parses_non_local_return_inside_block(self) -> None:
        program = parse("blk := [ ^ 1 ].")
        body = program.body
        assert body is not None
        stmt = body.statements[0]
        self.assertEqual(stmt.assignments, ["blk"])
        block = stmt.expression
        self.assertEqual(block.__class__.__name__, "BlockLiteral")
        self.assertEqual(len(block.body.statements), 1)
        self.assertTrue(block.body.statements[0].is_return)


if __name__ == "__main__":
    unittest.main()
