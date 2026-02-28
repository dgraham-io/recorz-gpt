from __future__ import annotations

from dataclasses import dataclass, field, fields, is_dataclass
from typing import Any


@dataclass
class Node:
    def to_dict(self) -> dict[str, Any]:
        return _to_dict(self)


@dataclass
class Program(Node):
    body: "ExecutableCode | None"


@dataclass
class ExecutableCode(Node):
    locals: list[str] = field(default_factory=list)
    primitive: int | None = None
    statements: list["Statement"] = field(default_factory=list)


@dataclass
class Statement(Node):
    assignments: list[str]
    expression: "Expression"
    is_return: bool = False


class Expression(Node):
    pass


@dataclass
class Reference(Expression):
    name: str


@dataclass
class ConstantLiteral(Expression):
    value: str


@dataclass
class IntegerLiteral(Expression):
    text: str


@dataclass
class ScaledDecimalLiteral(Expression):
    text: str


@dataclass
class FloatingPointLiteral(Expression):
    text: str


@dataclass
class CharacterLiteral(Expression):
    value: str


@dataclass
class StringLiteral(Expression):
    value: str


@dataclass
class SymbolLiteral(Expression):
    value: str


@dataclass
class ObjectArrayLiteral(Expression):
    elements: list[Expression]


@dataclass
class ByteArrayLiteral(Expression):
    elements: list[str]


@dataclass
class BlockLiteral(Expression):
    args: list[str]
    body: ExecutableCode


@dataclass
class NestedExpression(Expression):
    statement: Statement


@dataclass
class Message(Node):
    selector: str
    args: list[Expression]


@dataclass
class MessageSendChain(Expression):
    receiver: Expression
    messages: list[Message]


@dataclass
class Cascade(Expression):
    receiver: Expression
    chains: list[list[Message]]


def _to_dict(value: Any) -> Any:
    if is_dataclass(value):
        data = {"type": value.__class__.__name__}
        for item in fields(value):
            data[item.name] = _to_dict(getattr(value, item.name))
        return data
    if isinstance(value, list):
        return [_to_dict(item) for item in value]
    if isinstance(value, dict):
        return {k: _to_dict(v) for k, v in value.items()}
    return value
