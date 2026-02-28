from __future__ import annotations

import unittest
from pathlib import Path

import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from recorz.bytecode import (
    VM_CONST_INT,
    VM_CONST_STRING,
    VM_CONST_SYMBOL,
    VM_MAGIC,
    VM_OP_HALT,
    VM_OP_LOAD_CONST,
    VM_OP_LOAD_REF,
    VM_OP_SEND,
    VM_OP_STORE_REF,
    VM_VERSION,
    encode,
    serialize_vm_binary,
)
from recorz.parser import parse


class BytecodeTests(unittest.TestCase):
    def test_assignment_chain_preserves_expression_value(self) -> None:
        program = parse("a := b := 3.")
        chunk = encode(program)
        ops = [inst[0] for inst in chunk.instructions]
        self.assertIn("DUP", ops)
        self.assertEqual(ops.count("STORE_REF"), 2)

    def test_cascade_emits_dup_for_shared_receiver(self) -> None:
        program = parse("p x: 3; y: 4.")
        chunk = encode(program)
        ops = [inst[0] for inst in chunk.instructions]
        self.assertIn("DUP", ops)
        self.assertGreaterEqual(ops.count("SEND"), 2)

    def test_vm_binary_contains_header_and_halt(self) -> None:
        program = parse("1 print.")
        chunk = encode(program)
        blob = serialize_vm_binary(chunk)

        self.assertEqual(blob[:4], VM_MAGIC)
        self.assertEqual(blob[4], VM_VERSION)

        instr_count = blob[7]
        self.assertGreaterEqual(instr_count, 2)
        offset = _instruction_offset(blob)

        instructions = [blob[offset + i * 4 : offset + (i + 1) * 4] for i in range(instr_count)]
        self.assertEqual(instructions[0][0], VM_OP_LOAD_CONST)
        self.assertEqual(instructions[1][0], VM_OP_SEND)
        self.assertEqual(instructions[-1][0], VM_OP_HALT)

    def test_vm_binary_contains_ref_ops(self) -> None:
        program = parse("x := 7. x print.")
        blob = serialize_vm_binary(encode(program))

        instr_count = blob[7]
        offset = _instruction_offset(blob)

        instructions = [blob[offset + i * 4 : offset + (i + 1) * 4] for i in range(instr_count)]
        opcodes = [inst[0] for inst in instructions]
        self.assertIn(VM_OP_STORE_REF, opcodes)
        self.assertIn(VM_OP_LOAD_REF, opcodes)

    def test_vm_binary_encodes_binary_send_arity(self) -> None:
        program = parse("(40 + 2) print.")
        blob = serialize_vm_binary(encode(program))

        instr_count = blob[7]
        offset = _instruction_offset(blob)

        instructions = [blob[offset + i * 4 : offset + (i + 1) * 4] for i in range(instr_count)]
        sends = [inst for inst in instructions if inst[0] == VM_OP_SEND]
        self.assertGreaterEqual(len(sends), 2)
        self.assertIn(1, [inst[2] for inst in sends])

    def test_vm_binary_encodes_keyword_send_arity(self) -> None:
        program = parse("o addSlot: #answer value: 123.")
        blob = serialize_vm_binary(encode(program))

        instr_count = blob[7]
        offset = _instruction_offset(blob)

        instructions = [blob[offset + i * 4 : offset + (i + 1) * 4] for i in range(instr_count)]
        sends = [inst for inst in instructions if inst[0] == VM_OP_SEND]
        self.assertIn(2, [inst[2] for inst in sends])

    def test_vm_binary_encodes_typed_symbol_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("#answer.")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(constants, [(VM_CONST_SYMBOL, b"answer")])

    def test_vm_binary_encodes_typed_int_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("7.")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(constants, [(VM_CONST_INT, 7)])

    def test_vm_binary_encodes_typed_string_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("'hello'.")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(constants, [(VM_CONST_STRING, b"hello")])


def _decode_constants(blob: bytes) -> tuple[list[tuple[int, object]], int]:
    count = blob[5]
    offset = 8
    constants: list[tuple[int, object]] = []
    for _ in range(count):
        kind = blob[offset]
        offset += 1
        if kind == VM_CONST_INT:
            value = int.from_bytes(blob[offset : offset + 8], byteorder="little", signed=True)
            offset += 8
            constants.append((kind, value))
            continue
        if kind == VM_CONST_SYMBOL:
            size = blob[offset]
            offset += 1
            value = bytes(blob[offset : offset + size])
            offset += size
            constants.append((kind, value))
            continue
        if kind == VM_CONST_STRING:
            size = blob[offset]
            offset += 1
            value = bytes(blob[offset : offset + size])
            offset += size
            constants.append((kind, value))
            continue
        raise AssertionError(f"Unsupported constant kind in test decode: {kind}")
    return constants, offset


def _instruction_offset(blob: bytes) -> int:
    _, offset = _decode_constants(blob)
    selectors_count = blob[6]
    for _ in range(selectors_count):
        size = blob[offset]
        offset += 1 + size
    return offset


if __name__ == "__main__":
    unittest.main()
