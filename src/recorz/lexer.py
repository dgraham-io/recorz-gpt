from __future__ import annotations

from dataclasses import dataclass


BINARY_SELECTOR_CHARS = set("~!@%&*-+=|\\<>,?/")


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    position: int


class LexError(ValueError):
    pass


def lex(source: str) -> list[Token]:
    tokens: list[Token] = []
    i = 0
    n = len(source)

    while i < n:
        ch = source[i]

        if ch.isspace():
            i += 1
            continue

        if ch == '"':
            i = _consume_comment(source, i)
            continue

        if source.startswith(":=", i):
            tokens.append(Token("ASSIGN", ":=", i))
            i += 2
            continue

        if ch == "#" and i + 1 < n and source[i + 1] == "(":
            tokens.append(Token("HASH_LPAREN", "#(", i))
            i += 2
            continue

        if ch == "#" and i + 1 < n and source[i + 1] == "[":
            tokens.append(Token("HASH_LBRACKET", "#[", i))
            i += 2
            continue

        if ch == "#":
            symbol_token, i = _consume_symbol(source, i)
            tokens.append(symbol_token)
            continue

        if ch == "'":
            start = i
            text, i = _consume_string(source, i)
            tokens.append(Token("STRING", text, start))
            continue

        if ch == "$":
            if i + 1 >= n:
                raise LexError("Character literal missing character")
            tokens.append(Token("CHAR", source[i + 1], i))
            i += 2
            continue

        if ch == "(":
            tokens.append(Token("LPAREN", ch, i))
            i += 1
            continue
        if ch == ")":
            tokens.append(Token("RPAREN", ch, i))
            i += 1
            continue
        if ch == "[":
            tokens.append(Token("LBRACK", ch, i))
            i += 1
            continue
        if ch == "]":
            tokens.append(Token("RBRACK", ch, i))
            i += 1
            continue
        if ch == ".":
            tokens.append(Token("DOT", ch, i))
            i += 1
            continue
        if ch == ";":
            tokens.append(Token("SEMI", ch, i))
            i += 1
            continue
        if ch == "^":
            tokens.append(Token("CARET", ch, i))
            i += 1
            continue
        if ch == "|":
            tokens.append(Token("BAR", ch, i))
            i += 1
            continue
        if ch == ":":
            tokens.append(Token("COLON", ch, i))
            i += 1
            continue

        if _starts_number(source, i, tokens):
            start = i
            number, kind, i = _consume_number(source, i)
            tokens.append(Token(kind, number, start))
            continue

        if _is_ident_start(ch):
            ident, i = _consume_identifier(source, i)
            if i < n and source[i] == ":":
                tokens.append(Token("KEYWORD", ident + ":", i - len(ident)))
                i += 1
            else:
                tokens.append(Token("IDENT", ident, i - len(ident)))
            continue

        if ch in BINARY_SELECTOR_CHARS:
            start = i
            selector = ch
            if i + 1 < n and source[i + 1] in BINARY_SELECTOR_CHARS and source[i + 1] != "|":
                selector += source[i + 1]
                i += 1
            tokens.append(Token("BINARY", selector, start))
            i += 1
            continue

        raise LexError(f"Unexpected character {ch!r} at position {i}")

    tokens.append(Token("EOF", "", n))
    return tokens


def _consume_comment(source: str, i: int) -> int:
    i += 1
    n = len(source)
    while i < n and source[i] != '"':
        i += 1
    if i >= n:
        raise LexError("Unterminated comment")
    return i + 1


def _consume_string(source: str, i: int) -> tuple[str, int]:
    i += 1
    n = len(source)
    chars: list[str] = []
    while i < n:
        ch = source[i]
        if ch == "'":
            if i + 1 < n and source[i + 1] == "'":
                chars.append("'")
                i += 2
                continue
            return "".join(chars), i + 1
        chars.append(ch)
        i += 1
    raise LexError("Unterminated string literal")


def _consume_symbol(source: str, i: int) -> tuple[Token, int]:
    start = i
    i += 1
    if i >= len(source):
        raise LexError("Symbol literal missing body")

    if source[i] == "'":
        value, i = _consume_string(source, i)
        return Token("SYMBOL", value, start), i

    if source[i] in BINARY_SELECTOR_CHARS:
        selector = source[i]
        i += 1
        if i < len(source) and source[i] in BINARY_SELECTOR_CHARS and source[i] != "|":
            selector += source[i]
            i += 1
        return Token("SYMBOL", selector, start), i

    if not _is_ident_start(source[i]):
        raise LexError(f"Invalid symbol literal at position {start}")

    parts: list[str] = []
    ident, i = _consume_identifier(source, i)
    parts.append(ident)
    while i < len(source) and source[i] == ":":
        parts.append(":")
        i += 1
        if i < len(source) and _is_ident_start(source[i]):
            ident, i = _consume_identifier(source, i)
            parts.append(ident)
        else:
            break
    return Token("SYMBOL", "".join(parts), start), i


def _starts_number(source: str, i: int, tokens: list[Token]) -> bool:
    ch = source[i]
    if ch.isdigit():
        return True
    if ch != "-":
        return False
    if i + 1 >= len(source) or not source[i + 1].isdigit():
        return False
    prev = tokens[-1].kind if tokens else None
    return prev in {
        None,
        "ASSIGN",
        "LPAREN",
        "LBRACK",
        "HASH_LPAREN",
        "HASH_LBRACKET",
        "DOT",
        "SEMI",
        "COLON",
        "BAR",
        "CARET",
        "BINARY",
        "KEYWORD",
    }


def _consume_number(source: str, i: int) -> tuple[str, str, int]:
    start = i
    if source[i] == "-":
        i += 1

    i = _consume_digits(source, i)

    if i < len(source) and source[i] == "r":
        i += 1
        j = i
        while i < len(source) and source[i].isalnum():
            i += 1
        if i == j:
            raise LexError("Invalid radix literal")
        return source[start:i], "INTEGER", i

    if i < len(source) and source[i] == ".":
        if i + 1 < len(source) and source[i + 1].isdigit():
            i += 1
            i = _consume_digits(source, i)
            if i < len(source) and source[i] in "edq":
                i = _consume_exponent(source, i)
            if i < len(source) and source[i] == "s":
                i += 1
                j = i
                while i < len(source) and source[i].isdigit():
                    i += 1
                if i == j and i != len(source):
                    pass
                return source[start:i], "SCALED", i
            return source[start:i], "FLOAT", i

    if i < len(source) and source[i] in "edq":
        i = _consume_exponent(source, i)
        return source[start:i], "FLOAT", i

    if i < len(source) and source[i] == "s":
        i += 1
        while i < len(source) and source[i].isdigit():
            i += 1
        return source[start:i], "SCALED", i

    return source[start:i], "INTEGER", i


def _consume_exponent(source: str, i: int) -> int:
    i += 1
    if i < len(source) and source[i] in "+-":
        i += 1
    j = i
    i = _consume_digits(source, i)
    if i == j:
        raise LexError("Exponent is missing digits")
    return i


def _consume_digits(source: str, i: int) -> int:
    n = len(source)
    if i >= n or not source[i].isdigit():
        raise LexError("Expected decimal digits")
    while i < n and source[i].isdigit():
        i += 1
    return i


def _consume_identifier(source: str, i: int) -> tuple[str, int]:
    start = i
    i += 1
    while i < len(source) and _is_ident_continue(source[i]):
        i += 1
    return source[start:i], i


def _is_ident_start(ch: str) -> bool:
    return ch.isalpha() or ch == "_"


def _is_ident_continue(ch: str) -> bool:
    return ch.isalnum() or ch == "_"
