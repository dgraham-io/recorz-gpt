# VM Bootstrap Notes

## Build

```bash
make vm-build
```

Artifacts:
- `vm/build/recorz.elf`
- `vm/build/recorz.bin`

## Run in QEMU

```bash
make vm-run
```

Expected UART output includes:
- `recorz vm boot ok`
- `recorz primitives ready`
- `recorz interpreter loop`
- `123`
- `42`
- `38`
- `80`
- `20`
- `40` (fallback from `x / 0` via `primitiveFailed`)
- `recorz vm done`

## Primitive dispatch table

- `0`: no-op success
- `1`: UART putc primitive (byte in `a1`)
- `2`: debug break (`ebreak`)
- `10`: integer print primitive
- `11`: integer add
- `12`: integer subtract
- `13`: integer multiply
- `14`: integer divide
- `20`: object clone
- `24`: slot object `name`
- `25`: slot object `value`
- `26`: slot object `value:`
- `27`: object `addSlot:value:`
- `28`: object `slotNamed:`
- `31`: `primitiveFailed` fallback hook
- `3..9`, `15..19`, `21..23`, `29..30`, `32..255`: unimplemented (`-1` failure)

This table establishes a stable dispatch mechanism for the `<primitive: N>` language contract while behavior is filled in incrementally.

## Bytecode execution status

- VM now executes RCBC v2 bytecode generated from `vm/programs/smoke.rcz`.
- `SEND` resolves selectors via a prototype delegation chain (bootstrap prototypes: `ProtoObject` and `IntegerProto`) and executes method behavior through primitive dispatch.
- Current interpreter supports integer/symbol/string constants, `LOAD_REF`/`STORE_REF`, unary `print`, binary arithmetic sends (`+`, `-`, `*`, `/`), object slot protocol primitives (`clone`, `addSlot:value:`, `slotNamed:`), and primitive fallback to `primitiveFailed`.
- Remaining message semantics and object model integration are upcoming milestones.
