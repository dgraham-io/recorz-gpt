#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from recorz.bytecode import encode
from recorz.parser import parse_file


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate AST/bytecode fixtures.")
    parser.add_argument("input", help="Source file path")
    parser.add_argument("--ast-out", required=True, help="AST output JSON path")
    parser.add_argument("--bytecode-out", help="Optional bytecode output JSON path")
    args = parser.parse_args()

    program = parse_file(args.input)

    ast_path = Path(args.ast_out)
    ast_path.parent.mkdir(parents=True, exist_ok=True)
    ast_path.write_text(json.dumps(program.to_dict(), indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if args.bytecode_out:
        chunk = encode(program)
        bc_path = Path(args.bytecode_out)
        bc_path.parent.mkdir(parents=True, exist_ok=True)
        bc_path.write_text(json.dumps(chunk.to_dict(), indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
