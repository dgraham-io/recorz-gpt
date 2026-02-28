from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from . import ast
from .lexer import LexError, Token, lex


class ParseError(ValueError):
    pass


RESERVED = {"self", "super", "nil", "true", "false"}


@dataclass
class Parser:
    tokens: list[Token]
    pos: int = 0

    def parse_program(self) -> ast.Program:
        if self._at("EOF"):
            return ast.Program(body=None)
        body = self.parse_executable_code(stop_kinds={"EOF"})
        self._expect("EOF")
        return ast.Program(body=body)

    def parse_executable_code(self, stop_kinds: set[str]) -> ast.ExecutableCode:
        locals_: list[str] = []
        primitive: int | None = None

        if self._at("BAR"):
            locals_ = self._parse_locals()

        if self._at("BINARY") and self._peek().value == "<":
            primitive = self._parse_primitive_declaration()

        statements: list[ast.Statement] = []
        if not self._at_any(stop_kinds) and not self._at("DOT"):
            statements.append(self.parse_statement(stop_kinds))
            while self._match("DOT"):
                if self._at_any(stop_kinds) or self._at("DOT"):
                    continue
                statements.append(self.parse_statement(stop_kinds))

        return ast.ExecutableCode(locals=locals_, primitive=primitive, statements=statements)

    def parse_statement(self, stop_kinds: set[str]) -> ast.Statement:
        is_return = self._match("CARET")
        assignments: list[str] = []

        while self._at("IDENT") and self._peek(1).kind == "ASSIGN":
            name = self._advance().value
            if name in RESERVED:
                raise ParseError(f"Cannot assign to reserved identifier {name!r}")
            self._advance()  # :=
            assignments.append(name)

        expression = self.parse_expression(stop_kinds=stop_kinds)
        return ast.Statement(assignments=assignments, expression=expression, is_return=is_return)

    def parse_expression(self, stop_kinds: set[str]) -> ast.Expression:
        receiver = self.parse_operand(stop_kinds)

        first_chain = self._parse_message_chain(stop_kinds=stop_kinds, required=False)
        if first_chain is None:
            return receiver

        if not self._at("SEMI"):
            return ast.MessageSendChain(receiver=receiver, messages=first_chain)

        chains = [first_chain]
        while self._match("SEMI"):
            chain = self._parse_message_chain(stop_kinds=stop_kinds, required=True)
            chains.append(chain)
        return ast.Cascade(receiver=receiver, chains=chains)

    def parse_operand(self, stop_kinds: set[str]) -> ast.Expression:
        if self._at("LPAREN"):
            self._advance()
            nested = self.parse_statement(stop_kinds={"RPAREN"})
            self._expect("RPAREN")
            return ast.NestedExpression(statement=nested)

        if self._at("LBRACK"):
            return self._parse_block_literal()

        if self._at("HASH_LPAREN"):
            return self._parse_object_array_literal()

        if self._at("HASH_LBRACKET"):
            return self._parse_byte_array_literal()

        if self._at("IDENT"):
            ident = self._advance().value
            if ident in {"nil", "true", "false"}:
                return ast.ConstantLiteral(value=ident)
            return ast.Reference(name=ident)

        if self._at("INTEGER"):
            return ast.IntegerLiteral(text=self._advance().value)

        if self._at("SCALED"):
            return ast.ScaledDecimalLiteral(text=self._advance().value)

        if self._at("FLOAT"):
            return ast.FloatingPointLiteral(text=self._advance().value)

        if self._at("CHAR"):
            return ast.CharacterLiteral(value=self._advance().value)

        if self._at("STRING"):
            return ast.StringLiteral(value=self._advance().value)

        if self._at("SYMBOL"):
            return ast.SymbolLiteral(value=self._advance().value)

        token = self._peek()
        if token.kind in stop_kinds:
            raise ParseError(f"Expected operand before {token.kind}")
        raise ParseError(f"Expected operand, got {token.kind} at position {token.position}")

    def _parse_message_chain(self, stop_kinds: set[str], required: bool) -> list[ast.Message] | None:
        messages: list[ast.Message] = []

        while self._at("IDENT"):
            selector = self._advance().value
            messages.append(ast.Message(selector=selector, args=[]))

        while self._at("BINARY"):
            selector = self._advance().value
            arg = self._parse_binary_message_operand(stop_kinds)
            messages.append(ast.Message(selector=selector, args=[arg]))

        if self._at("KEYWORD"):
            selector_parts: list[str] = []
            args: list[ast.Expression] = []
            while self._at("KEYWORD"):
                selector_parts.append(self._advance().value)
                args.append(self._parse_keyword_message_argument(stop_kinds))
            messages.append(ast.Message(selector="".join(selector_parts), args=args))

        if required and not messages:
            token = self._peek()
            raise ParseError(f"Expected message chain before {token.kind}")
        return messages or None

    def _parse_binary_message_operand(self, stop_kinds: set[str]) -> ast.Expression:
        operand = self.parse_operand(stop_kinds)
        unary_messages: list[ast.Message] = []
        while self._at("IDENT"):
            unary_messages.append(ast.Message(selector=self._advance().value, args=[]))
        if unary_messages:
            return ast.MessageSendChain(receiver=operand, messages=unary_messages)
        return operand

    def _parse_keyword_message_argument(self, stop_kinds: set[str]) -> ast.Expression:
        receiver = self._parse_binary_message_operand(stop_kinds)
        more_messages: list[ast.Message] = []
        while self._at("BINARY"):
            selector = self._advance().value
            arg = self._parse_binary_message_operand(stop_kinds)
            more_messages.append(ast.Message(selector=selector, args=[arg]))
        if more_messages:
            return ast.MessageSendChain(receiver=receiver, messages=more_messages)
        return receiver

    def _parse_locals(self) -> list[str]:
        self._expect("BAR")
        names: list[str] = []
        while not self._at("BAR"):
            token = self._expect("IDENT")
            if token.value in RESERVED:
                raise ParseError(f"Local variable cannot use reserved name {token.value!r}")
            names.append(token.value)
        self._expect("BAR")
        return names

    def _parse_primitive_declaration(self) -> int:
        self._expect("BINARY", "<")
        self._expect("KEYWORD", "primitive:")
        number = self._expect("INTEGER")
        self._expect("BINARY", ">")
        return int(number.value)

    def _parse_block_literal(self) -> ast.BlockLiteral:
        self._expect("LBRACK")
        args: list[str] = []
        if self._at("COLON"):
            while self._match("COLON"):
                ident = self._expect("IDENT").value
                if ident in RESERVED:
                    raise ParseError(f"Block argument cannot use reserved name {ident!r}")
                args.append(ident)
            self._expect("BAR")

        body = self.parse_executable_code(stop_kinds={"RBRACK"})
        self._expect("RBRACK")
        return ast.BlockLiteral(args=args, body=body)

    def _parse_object_array_literal(self) -> ast.ObjectArrayLiteral:
        self._expect("HASH_LPAREN")
        elements: list[ast.Expression] = []
        while not self._at("RPAREN"):
            elements.append(self._parse_object_array_element())
        self._expect("RPAREN")
        return ast.ObjectArrayLiteral(elements=elements)

    def _parse_object_array_element(self) -> ast.Expression:
        if self._at("HASH_LPAREN"):
            return self._parse_object_array_literal()
        if self._at("SYMBOL"):
            return ast.SymbolLiteral(value=self._advance().value)
        if self._at("IDENT"):
            token = self._advance()
            if token.value in {"nil", "true", "false"}:
                return ast.ConstantLiteral(value=token.value)
            return ast.SymbolLiteral(value=token.value)
        if self._at("KEYWORD"):
            return ast.SymbolLiteral(value=self._advance().value)
        if self._at("BINARY"):
            return ast.SymbolLiteral(value=self._advance().value)
        if self._at("INTEGER"):
            return ast.IntegerLiteral(text=self._advance().value)
        if self._at("SCALED"):
            return ast.ScaledDecimalLiteral(text=self._advance().value)
        if self._at("FLOAT"):
            return ast.FloatingPointLiteral(text=self._advance().value)
        if self._at("CHAR"):
            return ast.CharacterLiteral(value=self._advance().value)
        if self._at("STRING"):
            return ast.StringLiteral(value=self._advance().value)
        raise ParseError(f"Invalid object array element at token {self._peek().kind}")

    def _parse_byte_array_literal(self) -> ast.ByteArrayLiteral:
        self._expect("HASH_LBRACKET")
        elements: list[str] = []
        while not self._at("RBRACK"):
            token = self._expect("INTEGER")
            if token.value.startswith("-"):
                raise ParseError("Byte array values must be unsigned")
            elements.append(token.value)
        self._expect("RBRACK")
        return ast.ByteArrayLiteral(elements=elements)

    def _peek(self, offset: int = 0) -> Token:
        idx = self.pos + offset
        if idx >= len(self.tokens):
            return self.tokens[-1]
        return self.tokens[idx]

    def _advance(self) -> Token:
        token = self._peek()
        self.pos += 1
        return token

    def _at(self, kind: str) -> bool:
        return self._peek().kind == kind

    def _at_any(self, kinds: Iterable[str]) -> bool:
        return self._peek().kind in kinds

    def _match(self, kind: str) -> bool:
        if self._at(kind):
            self.pos += 1
            return True
        return False

    def _expect(self, kind: str, value: str | None = None) -> Token:
        token = self._peek()
        if token.kind != kind:
            raise ParseError(f"Expected {kind}, got {token.kind} at position {token.position}")
        if value is not None and token.value != value:
            raise ParseError(f"Expected {kind} with value {value!r}, got {token.value!r}")
        self.pos += 1
        return token


def parse(source: str) -> ast.Program:
    return Parser(tokens=lex(source)).parse_program()


def parse_file(path: str) -> ast.Program:
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    return parse(source)


def parse_or_raise(source: str) -> ast.Program:
    try:
        return parse(source)
    except (LexError, ParseError):
        raise
