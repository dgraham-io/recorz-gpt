#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from recorz.bytecode import encode_to_vm_binary
from recorz.parser import parse_file


def main() -> None:
    parser = argparse.ArgumentParser(description="Compile recorz source into VM RCBC bytecode.")
    parser.add_argument("input", help="Input recorz source file")
    parser.add_argument("output", help="Output RCBC bytecode file")
    args = parser.parse_args()

    program = parse_file(args.input)
    blob = encode_to_vm_binary(program)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(blob)


if __name__ == "__main__":
    main()
