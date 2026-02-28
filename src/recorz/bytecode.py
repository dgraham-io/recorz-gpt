from __future__ import annotations

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

VM_OP_HALT = 0
VM_OP_LOAD_CONST = 1
VM_OP_DUP = 2
VM_OP_POP = 3
VM_OP_SEND = 4
VM_OP_RETURN = 5
VM_OP_LOAD_REF = 6
VM_OP_STORE_REF = 7


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
            self.emit("LOAD_CONST", self.add_constant(expr.text))
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
            for element in expr.elements:
                self.encode_expression(element)
            self.emit("MAKE_OBJECT_ARRAY", len(expr.elements))
            return
        if isinstance(expr, ast.ByteArrayLiteral):
            self.emit("LOAD_CONST", self.add_constant([int(v) for v in expr.elements]))
            return
        if isinstance(expr, ast.BlockLiteral):
            nested = Encoder()
            nested.encode_executable(expr.body)
            self.emit(
                "LOAD_CONST",
                self.add_constant(
                    {
                        "block": {
                            "args": expr.args,
                            "chunk": nested.chunk.to_dict(),
                        }
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

    def _encode_chain(self, receiver: ast.Expression, messages: list[ast.Message]) -> None:
        self.encode_expression(receiver)
        self._encode_messages_on_top(messages)

    def _encode_messages_on_top(self, messages: list[ast.Message]) -> None:
        for message in messages:
            for arg in message.args:
                self.encode_expression(arg)
            self.emit("SEND", self.add_selector(message.selector), len(message.args))

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
