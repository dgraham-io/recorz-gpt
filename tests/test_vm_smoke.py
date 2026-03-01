from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class VmSmokeTests(unittest.TestCase):
    def test_qemu_boot_banner(self) -> None:
        if shutil.which("qemu-system-riscv64") is None:
            self.skipTest("qemu-system-riscv64 not installed")
        if shutil.which("riscv64-unknown-elf-gcc") is None:
            self.skipTest("riscv64-unknown-elf-gcc not installed")

        subprocess.run(["make", "vm-build"], cwd=REPO_ROOT, check=True, capture_output=True, text=True)
        _assert_smoke_bytecode_has_refs(REPO_ROOT / "vm" / "generated" / "smoke.bc")

        cmd = [
            "qemu-system-riscv64",
            "-machine",
            "virt",
            "-nographic",
            "-bios",
            "none",
            "-kernel",
            str(REPO_ROOT / "vm" / "build" / "recorz.elf"),
            "-serial",
            "stdio",
            "-monitor",
            "none",
        ]

        output = ""
        try:
            result = subprocess.run(
                cmd,
                cwd=REPO_ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=2.0,
            )
            output = (result.stdout or "") + (result.stderr or "")
        except subprocess.TimeoutExpired as exc:
            output = _as_text(exc.stdout) + _as_text(exc.stderr)

        self.assertIn("recorz vm boot ok", output)
        self.assertIn("recorz primitives ready", output)
        self.assertIn("recorz interpreter loop", output)
        self.assertIn("123\n", output)
        self.assertIn("77\n", output)
        self.assertIn("12\n", output)
        self.assertIn("111\n", output)
        self.assertIn("255\n", output)
        self.assertIn("9\n", output)
        self.assertIn("7\n", output)
        self.assertIn("42\n", output)
        self.assertIn("38\n", output)
        self.assertIn("80\n", output)
        self.assertIn("20\n", output)
        self.assertIn("40\n", output)
        self.assertNotIn("unsupported send", output)
        self.assertNotIn("primitive failed", output)
        self.assertIn("recorz vm done", output)


def _as_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _assert_smoke_bytecode_has_refs(path: Path) -> None:
    blob = path.read_bytes()
    instr_count = blob[7]
    constants_count = blob[5]
    selectors_count = blob[6]

    offset = 8
    saw_symbol = False
    saw_string = False
    saw_float = False
    saw_scaled = False
    saw_block = False
    saw_object_array = False
    saw_byte_array = False
    for _ in range(constants_count):
        kind = blob[offset]
        offset += 1
        if kind == 0:
            offset += 8
            continue
        if kind == 1:
            size = blob[offset]
            offset += 1
            symbol = blob[offset : offset + size]
            offset += size
            if symbol == b"answer":
                saw_symbol = True
            continue
        if kind == 2:
            size = blob[offset]
            offset += 1
            value = blob[offset : offset + size]
            offset += size
            if value == b"ok":
                saw_string = True
            continue
        if kind == 3:
            payload = blob[offset : offset + 8]
            offset += 8
            if payload:
                saw_float = True
            continue
        if kind == 4:
            size = blob[offset]
            offset += 1
            value = blob[offset : offset + size]
            offset += size
            if value == b"-12.34s5":
                saw_scaled = True
            continue
        if kind == 5:
            size = int.from_bytes(blob[offset : offset + 2], byteorder="little", signed=False)
            offset += 2
            value = blob[offset : offset + size]
            offset += size
            if b"\"args\":[\"z\"]" in value:
                saw_block = True
            continue
        if kind == 6:
            size = int.from_bytes(blob[offset : offset + 2], byteorder="little", signed=False)
            offset += 2
            if size == 0:
                raise AssertionError("Smoke bytecode object-array payload is empty")
            count = blob[offset]
            value = blob[offset + 1 : offset + size]
            offset += size
            if len(value) == count and count == 3:
                saw_object_array = True
            continue
        if kind == 7:
            size = int.from_bytes(blob[offset : offset + 2], byteorder="little", signed=False)
            offset += 2
            value = blob[offset : offset + size]
            offset += size
            if value == b"\x01\x02\x03\xff":
                saw_byte_array = True
            continue
        raise AssertionError(f"Smoke bytecode contains unsupported constant kind: {kind}")
    if not saw_symbol:
        raise AssertionError("Smoke bytecode is missing #answer symbol constant")
    if not saw_string:
        raise AssertionError("Smoke bytecode is missing 'ok' string constant")
    if not saw_float:
        raise AssertionError("Smoke bytecode is missing float constant")
    if not saw_scaled:
        raise AssertionError("Smoke bytecode is missing scaled decimal constant")
    if not saw_block:
        raise AssertionError("Smoke bytecode is missing block constant")
    if not saw_object_array:
        raise AssertionError("Smoke bytecode is missing object-array constant")
    if not saw_byte_array:
        raise AssertionError("Smoke bytecode is missing byte-array constant")

    for _ in range(selectors_count):
        size = blob[offset]
        offset += 1 + size

    opcodes = [blob[offset + i * 4] for i in range(instr_count)]
    # LOAD_REF=6, STORE_REF=7
    if 6 not in opcodes or 7 not in opcodes:
        raise AssertionError("Smoke bytecode is missing LOAD_REF/STORE_REF opcodes")

    # SEND opcode=4 should include at least one binary arity send (op2 == 1).
    send_argcs = [blob[offset + i * 4 + 2] for i in range(instr_count) if blob[offset + i * 4] == 4]
    if 1 not in send_argcs:
        raise AssertionError("Smoke bytecode is missing binary SEND arity")
    if 2 not in send_argcs:
        raise AssertionError("Smoke bytecode is missing keyword SEND arity 2")


if __name__ == "__main__":
    unittest.main()
