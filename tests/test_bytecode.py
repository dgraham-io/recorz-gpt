from __future__ import annotations

import struct
import unittest
from pathlib import Path

import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from recorz.bytecode import (
    BLOCK_CONST_BLOCK,
    BLOCK_CONST_INT,
    BLOCK_CONST_STRING,
    BLOCK_CONST_SYMBOL,
    BLOCK_MAGIC,
    BLOCK_OP_DUP,
    BLOCK_OP_END,
    BLOCK_OP_POP,
    BLOCK_OP_PUSH_ARG,
    BLOCK_OP_PUSH_CONST,
    BLOCK_OP_PUSH_LOCAL,
    BLOCK_OP_PUSH_SELF,
    BLOCK_OP_PUSH_REF,
    BLOCK_OP_RETURN,
    BLOCK_OP_SEND,
    BLOCK_OP_STORE_LOCAL,
    BLOCK_OP_STORE_REF,
    BLOCK_VERSION,
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
from recorz.parser import parse, parse_file


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

    def test_vm_binary_encodes_three_keyword_send_arity(self) -> None:
        program = parse("m sum: 1 with: 2 and: 3.")
        blob = serialize_vm_binary(encode(program))

        instr_count = blob[7]
        offset = _instruction_offset(blob)

        instructions = [blob[offset + i * 4 : offset + (i + 1) * 4] for i in range(instr_count)]
        sends = [inst for inst in instructions if inst[0] == VM_OP_SEND]
        self.assertIn(3, [inst[2] for inst in sends])

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
        self.assertEqual(payload["magic"], BLOCK_MAGIC)
        self.assertEqual(payload["version"], BLOCK_VERSION)
        self.assertEqual(payload["args"], 1)
        self.assertEqual(len(payload["arg_refs"]), 1)
        self.assertEqual(payload["locals"], 0)
        self.assertEqual(len(payload["local_refs"]), 0)
        self.assertEqual(payload["constants"], [(BLOCK_CONST_INT, 1)])
        self.assertEqual(payload["selectors"], ["+"])
        self.assertEqual(
            payload["instructions"],
            [
                [BLOCK_OP_PUSH_ARG, 0, 0],
                [BLOCK_OP_PUSH_CONST, 0, 0],
                [BLOCK_OP_SEND, 0, 1],
                [BLOCK_OP_END, 0, 0],
            ],
        )

    def test_vm_binary_encodes_block_symbol_and_string_constants(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ #foo. 'bar' ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(
            payload["constants"],
            [
                (BLOCK_CONST_SYMBOL, b"foo"),
                (BLOCK_CONST_STRING, b"bar"),
            ],
        )
        self.assertEqual(
            payload["instructions"],
            [
                [BLOCK_OP_PUSH_CONST, 0, 0],
                [BLOCK_OP_POP, 0, 0],
                [BLOCK_OP_PUSH_CONST, 1, 0],
                [BLOCK_OP_END, 0, 0],
            ],
        )

    def test_vm_binary_encodes_block_captured_reference(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ x + 2 ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["selectors"], ["+"])
        self.assertEqual(
            payload["instructions"],
            [
                [BLOCK_OP_PUSH_REF, 0, 0],
                [BLOCK_OP_PUSH_CONST, 0, 0],
                [BLOCK_OP_SEND, 0, 1],
                [BLOCK_OP_END, 0, 0],
            ],
        )

    def test_vm_binary_encodes_block_assignment_store_ref(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ x := x + 1. x ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["selectors"], ["+"])
        self.assertEqual(
            payload["instructions"],
            [
                [BLOCK_OP_PUSH_REF, 0, 0],
                [BLOCK_OP_PUSH_CONST, 0, 0],
                [BLOCK_OP_SEND, 0, 1],
                [BLOCK_OP_DUP, 0, 0],
                [BLOCK_OP_STORE_REF, 0, 0],
                [BLOCK_OP_POP, 0, 0],
                [BLOCK_OP_PUSH_REF, 0, 0],
                [BLOCK_OP_END, 0, 0],
            ],
        )

    def test_vm_binary_encodes_block_local_assignment(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ | t | t := 1. t ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["locals"], 1)
        self.assertEqual(len(payload["local_refs"]), 1)
        self.assertEqual(payload["instructions"], [
            [BLOCK_OP_PUSH_CONST, 0, 0],
            [BLOCK_OP_DUP, 0, 0],
            [BLOCK_OP_STORE_LOCAL, 0, 0],
            [BLOCK_OP_POP, 0, 0],
            [BLOCK_OP_PUSH_LOCAL, 0, 0],
            [BLOCK_OP_END, 0, 0],
        ])

    def test_vm_binary_encodes_nested_block_capturing_outer_local(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ | t c | c := [ t := t + 2. t ]. c ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["locals"], 2)
        self.assertEqual(len(payload["local_refs"]), 2)
        self.assertIn([BLOCK_OP_STORE_LOCAL, 1, 0], payload["instructions"])

        nested_kind, nested_payload = payload["constants"][0]
        self.assertEqual(nested_kind, BLOCK_CONST_BLOCK)
        assert isinstance(nested_payload, dict)
        self.assertIn([BLOCK_OP_PUSH_REF, payload["local_refs"][0], 0], nested_payload["instructions"])
        self.assertIn([BLOCK_OP_STORE_REF, payload["local_refs"][0], 0], nested_payload["instructions"])

    def test_vm_binary_encodes_block_non_local_return(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ ^7. 8 ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["constants"], [(BLOCK_CONST_INT, 7)])
        self.assertEqual(
            payload["instructions"],
            [
                [BLOCK_OP_PUSH_CONST, 0, 0],
                [BLOCK_OP_RETURN, 0, 0],
                [BLOCK_OP_END, 0, 0],
            ],
        )

    def test_vm_binary_encodes_two_arg_block(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ :a :b | a + b ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["args"], 2)
        self.assertEqual(payload["selectors"], ["+"])
        self.assertEqual(
            payload["instructions"],
            [
                [BLOCK_OP_PUSH_ARG, 0, 0],
                [BLOCK_OP_PUSH_ARG, 1, 0],
                [BLOCK_OP_SEND, 0, 1],
                [BLOCK_OP_END, 0, 0],
            ],
        )

    def test_vm_binary_encodes_three_arg_block(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ :a :b :c | (a + b) + c ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["args"], 3)
        self.assertEqual(payload["selectors"], ["+"])
        self.assertEqual(
            payload["instructions"],
            [
                [BLOCK_OP_PUSH_ARG, 0, 0],
                [BLOCK_OP_PUSH_ARG, 1, 0],
                [BLOCK_OP_SEND, 0, 1],
                [BLOCK_OP_PUSH_ARG, 2, 0],
                [BLOCK_OP_SEND, 0, 1],
                [BLOCK_OP_END, 0, 0],
            ],
        )

    def test_vm_binary_encodes_block_send_arity_three(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ self sum: 1 with: 2 and: 3 ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertIn([BLOCK_OP_SEND, 0, 3], payload["instructions"])

    def test_vm_binary_encodes_nested_block_constant(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ :x | [ :y | x + y ] ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["args"], 1)
        self.assertEqual(len(payload["arg_refs"]), 1)
        self.assertEqual(payload["constants"][0][0], BLOCK_CONST_BLOCK)
        nested = payload["constants"][0][1]
        assert isinstance(nested, dict)
        self.assertEqual(nested["args"], 1)
        self.assertEqual(nested["selectors"], ["+"])

    def test_vm_binary_encodes_block_primitive_declaration(self) -> None:
        blob = serialize_vm_binary(encode(parse("[ :address | <primitive: 10> ^ self primitiveFailed ].")))
        constants, _ = _decode_constants(blob)
        self.assertEqual(len(constants), 1)
        kind, payload = constants[0]
        self.assertEqual(kind, VM_CONST_BLOCK)
        assert isinstance(payload, dict)
        self.assertEqual(payload["primitive"], 10)
        self.assertEqual(payload["args"], 1)
        self.assertIn([BLOCK_OP_PUSH_SELF, 0, 0], payload["instructions"])
        self.assertIn([BLOCK_OP_RETURN, 0, 0], payload["instructions"])

    def test_code_example_compiles_with_declared_primitives(self) -> None:
        program = parse_file(str(REPO_ROOT / "docs" / "code_example.md"))
        blob = serialize_vm_binary(encode(program))
        constants, _ = _decode_constants(blob)

        declared_primitives = [
            payload["primitive"]
            for kind, payload in constants
            if kind == VM_CONST_BLOCK and isinstance(payload, dict) and payload["primitive"] != 255
        ]
        self.assertIn(10, declared_primitives)
        self.assertIn(11, declared_primitives)

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
            value = _decode_block_payload(blob[offset : offset + size])
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


def _decode_block_payload(payload: bytes) -> dict[str, object]:
    if len(payload) < 8:
        raise AssertionError("Block payload is too short")
    if payload[:4] != BLOCK_MAGIC:
        raise AssertionError("Block payload has invalid magic")
    if payload[4] not in (2, BLOCK_VERSION):
        raise AssertionError("Block payload has invalid version")

    offset = 5
    primitive = 255
    if payload[4] >= 3:
        primitive = payload[offset]
        offset += 1
    args_count = payload[offset]
    offset += 1
    arg_ref_count = payload[offset]
    offset += 1
    arg_refs = list(payload[offset : offset + arg_ref_count])
    offset += arg_ref_count
    local_count = payload[offset]
    offset += 1
    local_ref_count = payload[offset]
    offset += 1
    local_refs = list(payload[offset : offset + local_ref_count])
    offset += local_ref_count

    constants_count = payload[offset]
    offset += 1
    constants: list[tuple[int, object]] = []
    for _ in range(constants_count):
        kind = payload[offset]
        offset += 1
        if kind == BLOCK_CONST_INT:
            value = int.from_bytes(payload[offset : offset + 8], byteorder="little", signed=True)
            offset += 8
            constants.append((kind, value))
            continue
        if kind in (BLOCK_CONST_SYMBOL, BLOCK_CONST_STRING):
            size = payload[offset]
            offset += 1
            value = bytes(payload[offset : offset + size])
            offset += size
            constants.append((kind, value))
            continue
        if kind == BLOCK_CONST_BLOCK:
            size = int.from_bytes(payload[offset : offset + 2], byteorder="little", signed=False)
            offset += 2
            value = _decode_block_payload(payload[offset : offset + size])
            offset += size
            constants.append((kind, value))
            continue
        raise AssertionError(f"Unsupported block constant kind: {kind}")

    selectors_count = payload[offset]
    offset += 1
    selectors: list[str] = []
    for _ in range(selectors_count):
        size = payload[offset]
        offset += 1
        selector = payload[offset : offset + size].decode("ascii")
        offset += size
        selectors.append(selector)

    instruction_count = payload[offset]
    offset += 1
    instructions: list[list[int]] = []
    for _ in range(instruction_count):
        instructions.append([payload[offset], payload[offset + 1], payload[offset + 2]])
        offset += 3

    if offset != len(payload):
        raise AssertionError("Block payload has trailing bytes")

    return {
        "magic": payload[:4],
        "version": payload[4],
        "primitive": primitive,
        "args": args_count,
        "arg_refs": arg_refs,
        "locals": local_count,
        "local_refs": local_refs,
        "constants": constants,
        "selectors": selectors,
        "instructions": instructions,
    }


def _instruction_offset(blob: bytes) -> int:
    _, offset = _decode_constants(blob)
    selectors_count = blob[6]
    for _ in range(selectors_count):
        size = blob[offset]
        offset += 1 + size
    return offset


if __name__ == "__main__":
    unittest.main()
