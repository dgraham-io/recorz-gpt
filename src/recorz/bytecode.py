from __future__ import annotations

import struct
from dataclasses import dataclass, field

from . import ast


@dataclass
class BytecodeChunk:
    constants: list[object] = field(default_factory=list)
    selectors: list[str] = field(default_factory=list)
    instructions: list[tuple] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "constants": self.constants,
            "selectors": self.selectors,
            "instructions": [list(inst) for inst in self.instructions],
        }


class EncodeError(ValueError):
    pass


VM_MAGIC = b"RCBC"
VM_VERSION = 2

VM_CONST_INT = 0
VM_CONST_SYMBOL = 1
VM_CONST_STRING = 2
VM_CONST_FLOAT = 3
VM_CONST_SCALED_DECIMAL = 4
VM_CONST_BLOCK = 5
VM_CONST_OBJECT_ARRAY = 6
VM_CONST_BYTE_ARRAY = 7

VM_OP_HALT = 0
VM_OP_LOAD_CONST = 1
VM_OP_DUP = 2
VM_OP_POP = 3
VM_OP_SEND = 4
VM_OP_RETURN = 5
VM_OP_LOAD_REF = 6
VM_OP_STORE_REF = 7

BLOCK_MAGIC = b"RBLK"
BLOCK_VERSION = 3

BLOCK_CONST_INT = 0
BLOCK_CONST_SYMBOL = 1
BLOCK_CONST_STRING = 2
BLOCK_CONST_BLOCK = 3

BLOCK_OP_END = 0
BLOCK_OP_PUSH_SELF = 1
BLOCK_OP_PUSH_ARG = 2
BLOCK_OP_PUSH_CONST = 3
BLOCK_OP_SEND = 4
BLOCK_OP_DUP = 5
BLOCK_OP_POP = 6
BLOCK_OP_PUSH_REF = 7
BLOCK_OP_STORE_REF = 8
BLOCK_OP_PUSH_LOCAL = 9
BLOCK_OP_STORE_LOCAL = 10
BLOCK_OP_RETURN = 11


class Encoder:
    def __init__(self) -> None:
        self.chunk = BytecodeChunk()
        self._selector_index: dict[str, int] = {}

    def encode_program(self, program: ast.Program) -> BytecodeChunk:
        if program.body is None:
            return self.chunk
        self.encode_executable(program.body)
        return self.chunk

    def encode_executable(self, code: ast.ExecutableCode) -> None:
        for idx, statement in enumerate(code.statements):
            self.encode_statement(statement)
            if not statement.is_return and idx != len(code.statements) - 1:
                self.emit("POP")

    def encode_statement(self, statement: ast.Statement) -> None:
        self.encode_expression(statement.expression)
        for name in reversed(statement.assignments):
            self.emit("DUP")
            self.emit("STORE_REF", self.add_symbol(name))
        if statement.is_return:
            self.emit("RETURN")

    def encode_expression(self, expr: ast.Expression) -> None:
        if isinstance(expr, ast.Reference):
            self.emit("LOAD_REF", self.add_symbol(expr.name))
            return
        if isinstance(expr, ast.ConstantLiteral):
            self.emit("LOAD_CONST", self.add_constant(expr.value))
            return
        if isinstance(expr, ast.IntegerLiteral):
            self.emit("LOAD_CONST", self.add_constant(int(expr.text)))
            return
        if isinstance(expr, ast.ScaledDecimalLiteral):
            self.emit("LOAD_CONST", self.add_constant({"scaled_decimal": expr.text}))
            return
        if isinstance(expr, ast.FloatingPointLiteral):
            self.emit("LOAD_CONST", self.add_constant(float(expr.text.replace("d", "e").replace("q", "e"))))
            return
        if isinstance(expr, ast.CharacterLiteral):
            self.emit("LOAD_CONST", self.add_constant(expr.value))
            return
        if isinstance(expr, ast.StringLiteral):
            self.emit("LOAD_CONST", self.add_constant(expr.value))
            return
        if isinstance(expr, ast.SymbolLiteral):
            self.emit("LOAD_CONST", self.add_constant({"symbol": expr.value}))
            return
        if isinstance(expr, ast.ObjectArrayLiteral):
            self.emit("LOAD_CONST", self._add_object_array_constant(expr))
            return
        if isinstance(expr, ast.ByteArrayLiteral):
            self.emit("LOAD_CONST", self.add_constant([int(v) for v in expr.elements]))
            return
        if isinstance(expr, ast.BlockLiteral):
            payload = self._encode_block_payload(expr)
            self.emit(
                "LOAD_CONST",
                self.add_constant(
                    {
                        "block_ir": payload,
                    }
                ),
            )
            return
        if isinstance(expr, ast.NestedExpression):
            self.encode_statement(expr.statement)
            return
        if isinstance(expr, ast.MessageSendChain):
            self._encode_chain(expr.receiver, expr.messages)
            return
        if isinstance(expr, ast.Cascade):
            self.encode_expression(expr.receiver)
            if not expr.chains:
                return
            for chain in expr.chains[:-1]:
                self.emit("DUP")
                self._encode_messages_on_top(chain)
                self.emit("POP")
            self._encode_messages_on_top(expr.chains[-1])
            return
        raise EncodeError(f"Unsupported expression type: {type(expr).__name__}")

    def _add_literal_constant(self, expr: ast.Expression) -> int:
        if isinstance(expr, ast.ObjectArrayLiteral):
            return self._add_object_array_constant(expr)
        return self.add_constant(self._literal_to_constant(expr))

    def _add_object_array_constant(self, expr: ast.ObjectArrayLiteral) -> int:
        element_indices = [self._add_literal_constant(element) for element in expr.elements]
        return self.add_constant({"object_array_indices": element_indices})

    def _literal_to_constant(self, expr: ast.Expression) -> object:
        if isinstance(expr, ast.ConstantLiteral):
            return expr.value
        if isinstance(expr, ast.IntegerLiteral):
            return int(expr.text)
        if isinstance(expr, ast.ScaledDecimalLiteral):
            return {"scaled_decimal": expr.text}
        if isinstance(expr, ast.FloatingPointLiteral):
            return float(expr.text.replace("d", "e").replace("q", "e"))
        if isinstance(expr, ast.CharacterLiteral):
            return expr.value
        if isinstance(expr, ast.StringLiteral):
            return expr.value
        if isinstance(expr, ast.SymbolLiteral):
            return {"symbol": expr.value}
        if isinstance(expr, ast.ByteArrayLiteral):
            return [int(v) for v in expr.elements]
        raise EncodeError(f"Unsupported literal array element type: {type(expr).__name__}")

    def _encode_chain(self, receiver: ast.Expression, messages: list[ast.Message]) -> None:
        self.encode_expression(receiver)
        self._encode_messages_on_top(messages)

    def _encode_messages_on_top(self, messages: list[ast.Message]) -> None:
        for message in messages:
            for arg in message.args:
                self.encode_expression(arg)
            self.emit("SEND", self.add_selector(message.selector), len(message.args))

    def _encode_block_payload(self, expr: ast.BlockLiteral) -> bytes:
        if len(expr.args) > 255:
            raise EncodeError("Block supports at most 255 arguments")
        if len(expr.body.locals) > 255:
            raise EncodeError("Block supports at most 255 locals")
        primitive_id = 255
        if expr.body.primitive is not None:
            if expr.body.primitive < 0 or expr.body.primitive > 255:
                raise EncodeError("Block primitive declaration must be in range 0..255")
            primitive_id = expr.body.primitive

        arg_indexes: dict[str, int] = {}
        arg_ref_indexes: list[int] = []
        for index, name in enumerate(expr.args):
            if name == "self":
                raise EncodeError("Block argument name 'self' is reserved")
            if name in arg_indexes:
                raise EncodeError(f"Duplicate block argument name: {name!r}")
            arg_indexes[name] = index
            arg_ref_indexes.append(self.add_symbol(name))
        local_indexes: dict[str, int] = {}
        local_ref_indexes: list[int] = []
        for index, name in enumerate(expr.body.locals):
            if name in local_indexes:
                raise EncodeError(f"Duplicate block local name: {name!r}")
            if name in arg_indexes:
                raise EncodeError(f"Block local shadows argument name: {name!r}")
            local_indexes[name] = index
            local_ref_indexes.append(self.add_symbol(name))

        constants: list[object] = []
        constant_indexes: dict[tuple[str, object], int] = {}
        selectors: list[str] = []
        selector_indexes: dict[str, int] = {}
        instructions: list[tuple[int, int, int]] = []

        for idx, statement in enumerate(expr.body.statements):
            self._encode_block_expression(
                statement.expression,
                arg_indexes,
                local_indexes,
                constants,
                constant_indexes,
                selectors,
                selector_indexes,
                instructions,
            )
            for name in reversed(statement.assignments):
                instructions.append((BLOCK_OP_DUP, 0, 0))
                local_index = local_indexes.get(name)
                if local_index is not None:
                    instructions.append((BLOCK_OP_STORE_LOCAL, local_index, 0))
                else:
                    instructions.append((BLOCK_OP_STORE_REF, self.add_symbol(name), 0))
            if statement.is_return:
                instructions.append((BLOCK_OP_RETURN, 0, 0))
                break
            if idx != len(expr.body.statements) - 1:
                instructions.append((BLOCK_OP_POP, 0, 0))

        instructions.append((BLOCK_OP_END, 0, 0))

        if len(constants) > 255:
            raise EncodeError("Block supports at most 255 constants")
        if len(selectors) > 255:
            raise EncodeError("Block supports at most 255 selectors")
        if len(instructions) > 255:
            raise EncodeError("Block supports at most 255 instructions")

        payload = bytearray()
        payload.extend(BLOCK_MAGIC)
        payload.append(BLOCK_VERSION)
        payload.append(primitive_id)
        payload.append(len(expr.args))
        payload.append(len(arg_ref_indexes))
        payload.extend(arg_ref_indexes)
        payload.append(len(local_indexes))
        payload.append(len(local_ref_indexes))
        payload.extend(local_ref_indexes)
        payload.append(len(constants))
        for value in constants:
            if isinstance(value, int):
                payload.append(BLOCK_CONST_INT)
                payload.extend(int(value).to_bytes(8, byteorder="little", signed=True))
                continue
            if isinstance(value, dict) and set(value.keys()) == {"symbol"} and isinstance(value["symbol"], str):
                symbol_bytes = value["symbol"].encode("ascii", errors="strict")
                if len(symbol_bytes) > 255:
                    raise EncodeError("Block symbol constant too long for VM block payload")
                payload.append(BLOCK_CONST_SYMBOL)
                payload.append(len(symbol_bytes))
                payload.extend(symbol_bytes)
                continue
            if isinstance(value, str):
                string_bytes = value.encode("utf-8", errors="strict")
                if len(string_bytes) > 255:
                    raise EncodeError("Block string constant too long for VM block payload")
                payload.append(BLOCK_CONST_STRING)
                payload.append(len(string_bytes))
                payload.extend(string_bytes)
                continue
            if (
                isinstance(value, dict)
                and set(value.keys()) == {"block_ir"}
                and isinstance(value["block_ir"], (bytes, bytearray))
            ):
                nested_block_bytes = bytes(value["block_ir"])
                if len(nested_block_bytes) > 65535:
                    raise EncodeError("Nested block constant too long for VM block payload")
                payload.append(BLOCK_CONST_BLOCK)
                payload.extend(len(nested_block_bytes).to_bytes(2, byteorder="little", signed=False))
                payload.extend(nested_block_bytes)
                continue
            raise EncodeError(f"Unsupported block constant type for VM payload: {value!r}")
        payload.append(len(selectors))
        for selector in selectors:
            selector_bytes = selector.encode("ascii", errors="strict")
            if len(selector_bytes) > 255:
                raise EncodeError("Block selector too long for VM block payload")
            payload.append(len(selector_bytes))
            payload.extend(selector_bytes)
        payload.append(len(instructions))
        for op, op1, op2 in instructions:
            payload.extend([op, op1, op2])
        return bytes(payload)

    def _encode_block_expression(
        self,
        expr: ast.Expression,
        arg_indexes: dict[str, int],
        local_indexes: dict[str, int],
        constants: list[object],
        constant_indexes: dict[tuple[str, object], int],
        selectors: list[str],
        selector_indexes: dict[str, int],
        instructions: list[tuple[int, int, int]],
    ) -> None:
        if isinstance(expr, ast.Reference):
            if expr.name == "self":
                instructions.append((BLOCK_OP_PUSH_SELF, 0, 0))
                return
            local_index = local_indexes.get(expr.name)
            if local_index is not None:
                instructions.append((BLOCK_OP_PUSH_LOCAL, local_index, 0))
                return
            arg_index = arg_indexes.get(expr.name)
            if arg_index is not None:
                instructions.append((BLOCK_OP_PUSH_ARG, arg_index, 0))
                return
            # Bootstrap closure semantics: treat non-argument references as captured refs
            # through the shared selector/global binding pool.
            ref_index = self.add_symbol(expr.name)
            instructions.append((BLOCK_OP_PUSH_REF, ref_index, 0))
            return
        if isinstance(expr, ast.IntegerLiteral):
            value = int(expr.text)
            const_key = ("int", value)
            const_index = constant_indexes.get(const_key)
            if const_index is None:
                if len(constants) >= 255:
                    raise EncodeError("Block supports at most 255 constants")
                constants.append(value)
                const_index = len(constants) - 1
                constant_indexes[const_key] = const_index
            instructions.append((BLOCK_OP_PUSH_CONST, const_index, 0))
            return
        if isinstance(expr, ast.SymbolLiteral):
            const_value = {"symbol": expr.value}
            const_key = ("symbol", expr.value)
            const_index = constant_indexes.get(const_key)
            if const_index is None:
                if len(constants) >= 255:
                    raise EncodeError("Block supports at most 255 constants")
                constants.append(const_value)
                const_index = len(constants) - 1
                constant_indexes[const_key] = const_index
            instructions.append((BLOCK_OP_PUSH_CONST, const_index, 0))
            return
        if isinstance(expr, ast.StringLiteral):
            const_key = ("string", expr.value)
            const_index = constant_indexes.get(const_key)
            if const_index is None:
                if len(constants) >= 255:
                    raise EncodeError("Block supports at most 255 constants")
                constants.append(expr.value)
                const_index = len(constants) - 1
                constant_indexes[const_key] = const_index
            instructions.append((BLOCK_OP_PUSH_CONST, const_index, 0))
            return
        if isinstance(expr, ast.BlockLiteral):
            nested_payload = self._encode_block_payload(expr)
            const_value = {"block_ir": nested_payload}
            const_key = ("block", nested_payload)
            const_index = constant_indexes.get(const_key)
            if const_index is None:
                if len(constants) >= 255:
                    raise EncodeError("Block supports at most 255 constants")
                constants.append(const_value)
                const_index = len(constants) - 1
                constant_indexes[const_key] = const_index
            instructions.append((BLOCK_OP_PUSH_CONST, const_index, 0))
            return
        if isinstance(expr, ast.MessageSendChain):
            self._encode_block_expression(
                expr.receiver,
                arg_indexes,
                local_indexes,
                constants,
                constant_indexes,
                selectors,
                selector_indexes,
                instructions,
            )
            for message in expr.messages:
                for argument in message.args:
                    self._encode_block_expression(
                        argument,
                        arg_indexes,
                        local_indexes,
                        constants,
                        constant_indexes,
                        selectors,
                        selector_indexes,
                        instructions,
                    )
                selector_index = selector_indexes.get(message.selector)
                if selector_index is None:
                    if len(selectors) >= 255:
                        raise EncodeError("Block supports at most 255 selectors")
                    selectors.append(message.selector)
                    selector_index = len(selectors) - 1
                    selector_indexes[message.selector] = selector_index
                instructions.append((BLOCK_OP_SEND, selector_index, len(message.args)))
            return
        if isinstance(expr, ast.NestedExpression):
            if expr.statement.assignments:
                raise EncodeError("Nested block expressions with assignments are not supported")
            if expr.statement.is_return:
                raise EncodeError("Nested block expressions with return are not supported")
            self._encode_block_expression(
                expr.statement.expression,
                arg_indexes,
                local_indexes,
                constants,
                constant_indexes,
                selectors,
                selector_indexes,
                instructions,
            )
            return
        if isinstance(expr, ast.Cascade):
            self._encode_block_expression(
                expr.receiver,
                arg_indexes,
                local_indexes,
                constants,
                constant_indexes,
                selectors,
                selector_indexes,
                instructions,
            )
            if not expr.chains:
                return
            for chain in expr.chains[:-1]:
                instructions.append((BLOCK_OP_DUP, 0, 0))
                for message in chain:
                    for argument in message.args:
                        self._encode_block_expression(
                            argument,
                            arg_indexes,
                            local_indexes,
                            constants,
                            constant_indexes,
                            selectors,
                            selector_indexes,
                            instructions,
                        )
                    selector_index = selector_indexes.get(message.selector)
                    if selector_index is None:
                        if len(selectors) >= 255:
                            raise EncodeError("Block supports at most 255 selectors")
                        selectors.append(message.selector)
                        selector_index = len(selectors) - 1
                        selector_indexes[message.selector] = selector_index
                    instructions.append((BLOCK_OP_SEND, selector_index, len(message.args)))
                instructions.append((BLOCK_OP_POP, 0, 0))
            for message in expr.chains[-1]:
                for argument in message.args:
                    self._encode_block_expression(
                        argument,
                        arg_indexes,
                        local_indexes,
                        constants,
                        constant_indexes,
                        selectors,
                        selector_indexes,
                        instructions,
                    )
                selector_index = selector_indexes.get(message.selector)
                if selector_index is None:
                    if len(selectors) >= 255:
                        raise EncodeError("Block supports at most 255 selectors")
                    selectors.append(message.selector)
                    selector_index = len(selectors) - 1
                    selector_indexes[message.selector] = selector_index
                instructions.append((BLOCK_OP_SEND, selector_index, len(message.args)))
            return
        raise EncodeError(f"Unsupported block expression type for VM payload: {type(expr).__name__}")

    def add_constant(self, value: object) -> int:
        self.chunk.constants.append(value)
        return len(self.chunk.constants) - 1

    def add_selector(self, selector: str) -> int:
        existing = self._selector_index.get(selector)
        if existing is not None:
            return existing
        self.chunk.selectors.append(selector)
        index = len(self.chunk.selectors) - 1
        self._selector_index[selector] = index
        return index

    def add_symbol(self, symbol: str) -> int:
        # References/selectors share one pool in RCBC.
        return self.add_selector(symbol)

    def emit(self, op: str, *operands: object) -> None:
        self.chunk.instructions.append((op, *operands))


def encode(program: ast.Program) -> BytecodeChunk:
    encoder = Encoder()
    return encoder.encode_program(program)


def encode_to_vm_binary(program: ast.Program) -> bytes:
    return serialize_vm_binary(encode(program))


def serialize_vm_binary(chunk: BytecodeChunk) -> bytes:
    """Serialize a chunk into the Phase 2 VM binary format (RCBC v2).

    Format:
    - 4 bytes magic: RCBC
    - 1 byte version
    - 1 byte constant count
    - 1 byte selector count
    - 1 byte instruction count
    - constants: typed entries:
      - kind:u8 == 0 (int), payload int64 little-endian
      - kind:u8 == 1 (symbol), payload len:u8 + ascii bytes
      - kind:u8 == 2 (string), payload len:u8 + utf-8 bytes
      - kind:u8 == 3 (float), payload IEEE754 float64 little-endian
      - kind:u8 == 4 (scaled_decimal), payload len:u8 + ascii bytes
      - kind:u8 == 5 (block), payload len:u16 + executable RBLK bytes
      - kind:u8 == 6 (object_array), payload len:u16 + [count:u8, const_index:u8 * count]
      - kind:u8 == 7 (byte_array), payload len:u16 + raw bytes
    - selectors: (len:u8, ascii bytes)
    - instructions: fixed 4-byte records [opcode, op1, op2, op3]
    """

    if len(chunk.constants) > 255:
        raise EncodeError("VM binary format supports at most 255 constants")
    if len(chunk.selectors) > 255:
        raise EncodeError("VM binary format supports at most 255 selectors")

    vm_instructions = list(chunk.instructions)
    if not vm_instructions or vm_instructions[-1][0] not in {"HALT", "RETURN"}:
        vm_instructions.append(("HALT",))

    if len(vm_instructions) > 255:
        raise EncodeError("VM binary format supports at most 255 instructions")

    encoded = bytearray()
    encoded.extend(VM_MAGIC)
    encoded.extend([
        VM_VERSION,
        len(chunk.constants),
        len(chunk.selectors),
        len(vm_instructions),
    ])

    for value in chunk.constants:
        if isinstance(value, int):
            if value < -(1 << 63) or value > (1 << 63) - 1:
                raise EncodeError(f"Integer constant out of int64 range: {value}")
            encoded.append(VM_CONST_INT)
            encoded.extend(int(value).to_bytes(8, byteorder="little", signed=True))
            continue

        if isinstance(value, dict) and set(value.keys()) == {"symbol"} and isinstance(value["symbol"], str):
            symbol_bytes = value["symbol"].encode("ascii", errors="strict")
            if len(symbol_bytes) > 255:
                raise EncodeError("Symbol constant too long for VM binary format")
            encoded.append(VM_CONST_SYMBOL)
            encoded.append(len(symbol_bytes))
            encoded.extend(symbol_bytes)
            continue

        if isinstance(value, str):
            string_bytes = value.encode("utf-8", errors="strict")
            if len(string_bytes) > 255:
                raise EncodeError("String constant too long for VM binary format")
            encoded.append(VM_CONST_STRING)
            encoded.append(len(string_bytes))
            encoded.extend(string_bytes)
            continue

        if isinstance(value, float):
            encoded.append(VM_CONST_FLOAT)
            encoded.extend(struct.pack("<d", value))
            continue

        if isinstance(value, dict) and set(value.keys()) == {"scaled_decimal"} and isinstance(value["scaled_decimal"], str):
            scaled_bytes = value["scaled_decimal"].encode("ascii", errors="strict")
            if len(scaled_bytes) > 255:
                raise EncodeError("Scaled decimal constant too long for VM binary format")
            encoded.append(VM_CONST_SCALED_DECIMAL)
            encoded.append(len(scaled_bytes))
            encoded.extend(scaled_bytes)
            continue

        if (
            isinstance(value, dict)
            and set(value.keys()) == {"block_ir"}
            and isinstance(value["block_ir"], (bytes, bytearray))
        ):
            block_bytes = bytes(value["block_ir"])
            _append_len_u16_constant(encoded, VM_CONST_BLOCK, block_bytes, "Block constant")
            continue

        if isinstance(value, dict) and set(value.keys()) == {"object_array_indices"}:
            indices = value["object_array_indices"]
            if not isinstance(indices, list):
                raise EncodeError("Object array constant indices must be a list")
            if len(indices) > 255:
                raise EncodeError("Object array constant supports at most 255 elements")
            payload = bytearray([len(indices)])
            for index in indices:
                payload.append(_u8_operand(index, "Object array constant index"))
            _append_len_u16_constant(encoded, VM_CONST_OBJECT_ARRAY, bytes(payload), "Object array constant")
            continue

        if (
            isinstance(value, list)
            and all(isinstance(element, int) for element in value)
            and all(0 <= element <= 255 for element in value)
        ):
            byte_array_bytes = bytes(value)
            _append_len_u16_constant(encoded, VM_CONST_BYTE_ARRAY, byte_array_bytes, "Byte array constant")
            continue

        raise EncodeError(f"VM binary constant is not yet supported: {value!r}")

    for selector in chunk.selectors:
        selector_bytes = selector.encode("ascii", errors="strict")
        if len(selector_bytes) > 255:
            raise EncodeError("Selector too long for VM binary format")
        encoded.append(len(selector_bytes))
        encoded.extend(selector_bytes)

    for instruction in vm_instructions:
        op = instruction[0]
        op1 = 0
        op2 = 0
        op3 = 0

        if op == "HALT":
            opcode = VM_OP_HALT
        elif op == "LOAD_CONST":
            opcode = VM_OP_LOAD_CONST
            op1 = _u8_operand(instruction[1], "LOAD_CONST index")
        elif op == "DUP":
            opcode = VM_OP_DUP
        elif op == "POP":
            opcode = VM_OP_POP
        elif op == "SEND":
            opcode = VM_OP_SEND
            op1 = _u8_operand(instruction[1], "SEND selector index")
            op2 = _u8_operand(instruction[2], "SEND argument count")
        elif op == "RETURN":
            opcode = VM_OP_RETURN
        elif op == "LOAD_REF":
            opcode = VM_OP_LOAD_REF
            op1 = _u8_operand(instruction[1], "LOAD_REF symbol index")
        elif op == "STORE_REF":
            opcode = VM_OP_STORE_REF
            op1 = _u8_operand(instruction[1], "STORE_REF symbol index")
        else:
            raise EncodeError(f"Instruction {op!r} is not yet supported by VM binary format")

        encoded.extend([opcode, op1, op2, op3])

    return bytes(encoded)


def _u8_operand(value: object, label: str) -> int:
    if not isinstance(value, int):
        raise EncodeError(f"{label} must be an integer")
    if value < 0 or value > 255:
        raise EncodeError(f"{label} must be within 0..255")
    return value


def _append_len_u16_constant(encoded: bytearray, kind: int, payload: bytes, label: str) -> None:
    if len(payload) > 65535:
        raise EncodeError(f"{label} too long for VM binary format")
    encoded.append(kind)
    encoded.extend(len(payload).to_bytes(2, byteorder="little", signed=False))
    encoded.extend(payload)
