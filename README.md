# recorz-gpt

## Phase 1 tooling

Hosted parser/bytecode tooling lives under `src/recorz`.

Run tests:

```bash
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

Generate AST/bytecode fixtures:

```bash
PYTHONPATH=src python3 scripts/generate_fixture.py \
  docs/code_example.md \
  --ast-out docs/fixtures/code_example.ast.json \
  --bytecode-out docs/fixtures/code_example.bytecode.json
```

## Phase 2 bootstrap VM

Build and run the RISC-V VM bootstrap under QEMU:

```bash
make vm-build
make vm-run
```

`make vm-build` compiles `vm/programs/smoke.rcz` into RCBC bytecode and links it into the VM image.

Current smoke program exercises:
- global assignment/read (`LOAD_REF` / `STORE_REF`)
- prototype object cloning (`Object clone`)
- object slot protocol (`addSlot:value:` / `slotNamed:`) using symbol keys (`#answer`)
- typed VM constants (`int`, `symbol`, `string`, `float`, `scaled-decimal`, `block`, `object-array`, `byte-array`) including `'ok'`, `1e+3`, `-12.34s5`, `[ :z | z + 1 ]`, `#(1 #answer 'ok')`, and `#[1 2 3 255]` smoke literal decode
- payload protocol primitives (`size`, `at:`, `at:put:`) for strings, byte arrays, and object arrays
- executable block activation (`value`, `value:`) for lexical `self`/arg dispatch, block-local slots, bootstrap captured/global refs, nested-block lexical arg/local capture, shared sibling-closure capture envs, captured-ref mutation in closure-producing methods, and block non-local return unwind
- dynamic method execution through block bodies (`addMethod:do:`) across unary/binary/multi-keyword selector arities
- unary `print`
- integer arithmetic sends (`+`, `-`, `*`, `/`)
- primitive fallback path (`primitiveFailed`) via divide-by-zero recovery

Additional dedicated VM runtime programs under `vm/programs/` exercise:
- escaped non-local return recovery (`cannot_return.rcz`)
- `doesNotUnderstand:argc:` fallback at top-level and in method/block execution (`dnu.rcz`)
- image snapshot/restore v0 (`image.rcz`)
- serial host image bridge roundtrip (`image_host_export.rcz` + `image_host_import.rcz`)

## Host image bridge workflow

Export image bytes from an export program build into a file:

```bash
make -C vm all PROGRAM_SRC=programs/image_host_export.rcz
python3 scripts/qemu_image_bridge.py export \
  --elf vm/build/recorz.elf \
  --out vm/generated/session.rcim
```

Import image bytes into an import program build from a file:

```bash
make -C vm all PROGRAM_SRC=programs/image_host_import.rcz
python3 scripts/qemu_image_bridge.py import \
  --elf vm/build/recorz.elf \
  --image vm/generated/session.rcim \
  --expect "10"
```

Bridge/image compatibility and versioning policy is documented in:
- `docs/image_compatibility.md`
