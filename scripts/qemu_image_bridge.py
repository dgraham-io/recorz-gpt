#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def bridge_checksum(blob: bytes) -> int:
    checksum = 0
    for value in blob:
        checksum = (checksum + value) & 0xFFFFFFFF
    return checksum


def parse_bridge_payload(output: str) -> tuple[int, int, bytes]:
    match = re.search(r"RCIMG ([0-9]+) ([0-9a-fA-F]{8})\n([0-9a-fA-F]+)\n", output)
    if match is None:
        raise ValueError("Bridge image payload not found in QEMU output")
    image_len = int(match.group(1))
    image_checksum = int(match.group(2), 16)
    image_hex = match.group(3).lower()
    blob = bytes.fromhex(image_hex)
    if len(blob) != image_len:
        raise ValueError(f"Length mismatch: header={image_len}, payload={len(blob)}")
    actual_checksum = bridge_checksum(blob)
    if actual_checksum != image_checksum:
        raise ValueError(
            f"Checksum mismatch: header=0x{image_checksum:08x}, actual=0x{actual_checksum:08x}"
        )
    return image_len, image_checksum, blob


def make_bridge_input(blob: bytes) -> str:
    checksum = bridge_checksum(blob)
    return f"{len(blob)} {checksum:08x}\n{blob.hex()}\n"


def run_qemu(elf: Path, timeout: float, bridge_input: str | None = None, qemu_bin: str = "qemu-system-riscv64") -> str:
    cmd = [
        qemu_bin,
        "-machine",
        "virt",
        "-nographic",
        "-bios",
        "none",
        "-kernel",
        str(elf),
        "-serial",
        "stdio",
        "-monitor",
        "none",
    ]
    try:
        result = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
            input=bridge_input,
            timeout=timeout,
        )
        return (result.stdout or "") + (result.stderr or "")
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode("utf-8", errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        return stdout + stderr


def cmd_export(args: argparse.Namespace) -> int:
    output = run_qemu(args.elf, args.timeout, qemu_bin=args.qemu_bin)
    if args.log_out is not None:
        args.log_out.write_text(output, encoding="utf-8")
    _, checksum, blob = parse_bridge_payload(output)
    args.out.write_bytes(blob)
    print(f"wrote {len(blob)} bytes to {args.out} (sum32=0x{checksum:08x})")
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    blob = args.image.read_bytes()
    bridge_input = make_bridge_input(blob)
    output = run_qemu(args.elf, args.timeout, bridge_input=bridge_input, qemu_bin=args.qemu_bin)
    if args.log_out is not None:
        args.log_out.write_text(output, encoding="utf-8")
    sys.stdout.write(output)
    if args.expect is not None and args.expect not in output:
        print(f"\nexpected marker not found: {args.expect!r}", file=sys.stderr)
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Export/import recorz VM images over the RCIMG UART bridge.")
    parser.add_argument("--qemu-bin", default="qemu-system-riscv64", help="QEMU binary (default: qemu-system-riscv64)")
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export", help="Run QEMU and extract RCIMG payload into a binary image file.")
    export_parser.add_argument("--elf", type=Path, required=True, help="Path to VM ELF built with an export program.")
    export_parser.add_argument("--out", type=Path, required=True, help="Output image file path.")
    export_parser.add_argument("--timeout", type=float, default=45.0, help="QEMU timeout in seconds.")
    export_parser.add_argument("--log-out", type=Path, help="Optional full QEMU log output file.")
    export_parser.set_defaults(func=cmd_export)

    import_parser = subparsers.add_parser("import", help="Run QEMU and feed an image file to importImage bridge input.")
    import_parser.add_argument("--elf", type=Path, required=True, help="Path to VM ELF built with an import program.")
    import_parser.add_argument("--image", type=Path, required=True, help="Input image file path.")
    import_parser.add_argument("--timeout", type=float, default=45.0, help="QEMU timeout in seconds.")
    import_parser.add_argument("--expect", help="Optional substring that must appear in VM output.")
    import_parser.add_argument("--log-out", type=Path, help="Optional full QEMU log output file.")
    import_parser.set_defaults(func=cmd_import)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except Exception as exc:  # pragma: no cover
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
