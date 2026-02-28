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
- typed VM constants (`int`, `symbol`, `string`) including `'ok'` smoke literal decode
- unary `print`
- integer arithmetic sends (`+`, `-`, `*`, `/`)
- primitive fallback path (`primitiveFailed`) via divide-by-zero recovery
