from __future__ import annotations

import json
import struct
import unittest
from pathlib import Path

import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from recorz.bytecode import (
    VM_CONST_BLOCK,
    VM_CONST_BYTE_ARRAY,
    VM_CONST_INT,
    VM_CONST_FLOAT,
    VM_CONST_OBJECT_ARRAY,
    VM_CONST_SCALED_DECIMAL,
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

    def test_vm_binary_encodes_typed_float_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("1e+3.")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(constants, [(VM_CONST_FLOAT, 1000.0)])

    def test_vm_binary_encodes_typed_scaled_decimal_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("-12.34s5.")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(constants, [(VM_CONST_SCALED_DECIMAL, b"-12.34s5")])

    def test_vm_binary_encodes_typed_block_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ :x | x + 1 ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["args"], ["x"])
        self.assertIn("instructions", payload["chunk"])

    def test_vm_binary_encodes_typed_object_array_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("#(1 #foo 'bar').")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 4)
        self.assertEqual(constants[0], (VM_CONST_INT, 1))
        self.assertEqual(constants[1], (VM_CONST_SYMBOL, b"foo"))
        self.assertEqual(constants[2], (VM_CONST_STRING, b"bar"))
        self.assertEqual(constants[3], (VM_CONST_OBJECT_ARRAY, [0, 1, 2]))

    def test_vm_binary_encodes_typed_byte_array_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("#[1 2 255].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(constants, [(VM_CONST_BYTE_ARRAY, b"\x01\x02\xff")])


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
        if kind == VM_CONST_FLOAT:
            value = struct.unpack("<d", blob[offset : offset + 8])[0]
            offset += 8
            constants.append((kind, value))
            continue
        if kind == VM_CONST_SCALED_DECIMAL:
            size = blob[offset]
            offset += 1
            value = bytes(blob[offset : offset + size])
            offset += size
            constants.append((kind, value))
            continue
        if kind == VM_CONST_BLOCK:
            size = int.from_bytes(blob[offset : offset + 2], byteorder="little", signed=False)
            offset += 2
            value = json.loads(blob[offset : offset + size].decode("utf-8"))
            offset += size
            constants.append((kind, value))
            continue
        if kind == VM_CONST_OBJECT_ARRAY:
            size = int.from_bytes(blob[offset : offset + 2], byteorder="little", signed=False)
            offset += 2
            if size == 0:
                raise AssertionError("Object array payload must include element-count byte")
            count = blob[offset]
            value = list(blob[offset + 1 : offset + size])
            if len(value) != count:
                raise AssertionError("Object array payload length does not match encoded count")
            offset += size
            constants.append((kind, value))
            continue
        if kind == VM_CONST_BYTE_ARRAY:
            size = int.from_bytes(blob[offset : offset + 2], byteorder="little", signed=False)
            offset += 2
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
