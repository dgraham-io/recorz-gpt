# recorz Usage Guide

This guide is for experimenting with the current bootstrap system on macOS with QEMU.

## 1. Prerequisites

Required tools:
- `python3`
- `qemu-system-riscv64`
- `riscv64-unknown-elf-gcc`
- `riscv64-unknown-elf-objcopy`
- `make`

Quick checks:

```bash
python3 --version
qemu-system-riscv64 --version
riscv64-unknown-elf-gcc --version
```

## 2. Run Host-Side Tests

From repository root:

```bash
make test-host
```

This runs parser/bytecode tests and VM smoke tests (including QEMU-based tests when QEMU/toolchain are available).

## 3. Build and Run the Default VM Program

Build:

```bash
make vm-build
```

Run:

```bash
make vm-run
```

This compiles `vm/programs/smoke.rcz` to `vm/generated/program.bc`, links `vm/build/recorz.elf`, then boots the VM in QEMU with UART output.

## 4. Try Your Own `.rcz` Program

The VM Makefile supports selecting a source program:

```bash
make -C vm all PROGRAM_SRC=programs/smoke.rcz
scripts/run_qemu_vm.sh vm/build/recorz.elf
```

To run a different file already in the repo:

```bash
make -C vm all PROGRAM_SRC=programs/dnu.rcz
scripts/run_qemu_vm.sh vm/build/recorz.elf
```

Selector-coverage gate program:

```bash
make -C vm all PROGRAM_SRC=programs/protocol_core.rcz
scripts/run_qemu_vm.sh vm/build/recorz.elf
```

You can also compile a doc/sample source directly:

```bash
make -C vm all PROGRAM_SRC=../docs/code_example.md
scripts/run_qemu_vm.sh vm/build/recorz.elf
```

## 5. Fast Edit Loop for Experiments

Suggested loop:
1. Edit `vm/programs/smoke.rcz` or another `.rcz` file.
2. Rebuild:

```bash
make -C vm all PROGRAM_SRC=programs/smoke.rcz
```

3. Run:

```bash
scripts/run_qemu_vm.sh vm/build/recorz.elf
```

4. If behavior looks wrong, run focused tests:

```bash
PYTHONPATH=src python3 -m unittest -v tests.test_bytecode
PYTHONPATH=src python3 -m unittest -v tests.test_vm_smoke.VmSmokeTests.test_qemu_boot_banner
```

## 6. Image Export/Import Workflow

Export image bytes from VM to host file:

```bash
make -C vm all PROGRAM_SRC=programs/image_host_export.rcz
python3 scripts/qemu_image_bridge.py export \
  --elf vm/build/recorz.elf \
  --out vm/generated/session.rcim
```

Import image bytes back into VM:

```bash
make -C vm all PROGRAM_SRC=programs/image_host_import.rcz
python3 scripts/qemu_image_bridge.py import \
  --elf vm/build/recorz.elf \
  --image vm/generated/session.rcim \
  --expect "10"
```

If `--expect` is provided and missing from output, the import command exits non-zero.

## 7. Fixtures and Compiler Output

Regenerate AST and hosted-bytecode fixtures for `docs/code_example.md`:

```bash
make fixture
```

Compile any source file to VM RCBC bytecode blob:

```bash
PYTHONPATH=src python3 scripts/compile_vm_bytecode.py \
  docs/code_example.md \
  /tmp/code_example.bc
```

## 8. What Works Well Right Now

Current stable experimentation areas:
- prototype cloning and slots (`clone`, `addSlot:value:`, `slotNamed:`)
- method blocks via `addMethod:do:`
- block evaluation (`value`, `value:`)
- lexical capture, mutable captures, and non-local return handling
- integer arithmetic and `print`
- image save/load with serial host bridge

## 9. Known Limitations During Experiments

Expected limitations in this bootstrap:
- many Smalltalk-library style selectors are not implemented yet (missing sends route to `doesNotUnderstand:argc:` diagnostics)
- object model/runtime behavior is intentionally partial and still evolving
- no full graphical VM/workspace stack yet (serial-first bootstrap)
- raw UART bridge is development-oriented, not production transport

See `docs/remaining_work.md` for detailed roadmap and completion criteria.
