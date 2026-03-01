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
- `77`
- `12`
- `11`
- `6`
- `60`
- `19`
- `10`
- `201`
- `211`
- `212`
- `502`
- `111`
- `255`
- `9`
- `3`
- `8`
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
- `40`: bytes-like `size`
- `41`: bytes-like `at:`
- `42`: bytes-like `at:put:`
- `43`: object-array `size`
- `44`: object-array `at:`
- `45`: object-array `at:put:`
- `46`: block `value`
- `47`: block `value:`
- `48`: `CannotReturn` print primitive
- `49`: default `onCannotReturn:` pass-through
- `50`: `CannotReturn` `onCannotReturn:` handler dispatch
- `51`: `doesNotUnderstand:argc:` debug fallback
- `128`: `saveImage` (snapshot state to image byte array)
- `129`: `loadImage:` (restore state from image byte array)
- `130`: `exportImage:` (emit image bytes over UART as `RCIMG <len> <sum32hex>\\n<hex>`)
- `131`: `importImage` (read UART bridge payload, verify `sum32`, return byte array)
- `132`: `saveImageToHost` (snapshot + bridge export)
- `133`: `loadImageFromHost` (bridge import + restore)
- `3..9`, `15..19`, `21..23`, `29..30`, `32..39`, `52..127`, `134..255`: unimplemented (`-1` failure)

This table establishes a stable dispatch mechanism for the `<primitive: N>` language contract while behavior is filled in incrementally.

## Bytecode execution status

- VM now executes RCBC v2 bytecode generated from `vm/programs/smoke.rcz`.
- `SEND` resolves selectors via a prototype delegation chain (bootstrap prototypes: `ProtoObject` and `IntegerProto`) and executes method behavior through primitive dispatch.
- Current interpreter supports integer/symbol/string/float/scaled-decimal/block/object-array/byte-array constants, `LOAD_REF`/`STORE_REF`, unary `print`, binary arithmetic sends (`+`, `-`, `*`, `/`), payload collection protocol primitives (`size`, `at:`, `at:put:`), executable block activation (`value`, `value:`) and dynamic method block execution across send arities (including multi-keyword selectors) with bootstrap captured/global refs, nested block constants, shared activation closure env capture for sibling closures, block-local slots (`PUSH_LOCAL`, `STORE_LOCAL`), captured arg/local mutation via block `STORE_REF`, block non-local return unwind via `RETURN` plus home-activation validity checks (escaped return recovers to a first-class runtime `CannotReturn` object with `onCannotReturn:` handling), object slot protocol primitives (`clone`, `addSlot:value:`, `slotNamed:`), message-miss fallback via `doesNotUnderstand:argc:` with serial debug selector/arity output (including sends executed inside method/closure block evaluation), in-VM image snapshot/restore primitives (`saveImage`, `loadImage:`), and host-bridge convenience primitives (`saveImageToHost`, `loadImageFromHost`).
- Image snapshot format is `RCIM` v2 and now includes VM-owned symbol/block literal storage plus root-object state, enabling serial export/import roundtrips across separate export/import program builds.
- `recorz_program_blob` now links in a dedicated `.program` section after VM state sections so heap/root addresses remain stable even when bytecode size changes.
- Remaining message semantics and object model integration are upcoming milestones.
