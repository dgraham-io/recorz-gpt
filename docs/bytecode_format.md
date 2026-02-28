# recorz Bytecode Format (v0 hosted + v2 VM binary)

Phase 1 and Phase 2 use two related forms:

- Hosted IR (`BytecodeChunk` in Python): symbolic instructions for tests and tooling.
- VM binary (`RCBC` v2): compact byte stream executed by the RISC-V interpreter.

## Hosted IR chunk layout

A hosted chunk has:
- `constants`: literal pool
- `selectors`: shared symbol pool (message selectors and variable names)
- `instructions`: symbolic instruction stream

Hosted instruction set (current):
- `LOAD_CONST <const_index>`
- `LOAD_REF <symbol_index>`
- `STORE_REF <symbol_index>`
- `SEND <selector_index> <argc>`
- `MAKE_OBJECT_ARRAY <count>`
- `DUP`
- `POP`
- `RETURN`

## VM binary format (`RCBC` v2)

Binary layout:
- `magic[4]`: ASCII `RCBC`
- `version[1]`: `2`
- `constant_count[1]`
- `selector_count[1]`
- `instruction_count[1]`
- constants: `constant_count` typed entries:
  - `kind:u8 = 0` -> signed little-endian `int64`
  - `kind:u8 = 1` -> symbol payload `(len:u8, ascii bytes)`
  - `kind:u8 = 2` -> string payload `(len:u8, utf-8 bytes)`
- selectors: repeated `(len:u8, ascii bytes)`
- instructions: `instruction_count` entries, each 4 bytes:
  - `opcode:u8`
  - `op1:u8`
  - `op2:u8`
  - `op3:u8` (reserved)

VM opcodes:
- `0`: `HALT`
- `1`: `LOAD_CONST` (`op1=constant index`)
- `2`: `DUP`
- `3`: `POP`
- `4`: `SEND` (`op1=selector index`, `op2=argc`)
- `5`: `RETURN`
- `6`: `LOAD_REF` (`op1=symbol index`)
- `7`: `STORE_REF` (`op1=symbol index`)

## Current execution support in VM

The bootstrap interpreter currently supports:
- integer constants
- symbol constants (interned as symbol objects)
- string constants (heap string objects with byte pointer + length metadata)
- unary `SEND print` (argc `0`) -> UART decimal output
- binary arithmetic sends (argc `1`) for selectors `+`, `-`, `*`, `/`
- keyword sends (argc `2`) for bootstrap slot protocol (`addSlot:value:`)
- global variable bindings via `LOAD_REF`/`STORE_REF`
- stack operations (`LOAD_CONST`, `DUP`, `POP`, `RETURN`, `HALT`)

Unsupported instructions/selectors currently raise VM diagnostics over UART.

## Compatibility notes

- Serializer appends `HALT` if not already terminated by `HALT` or `RETURN`.
- RCBC v2 limits counts/operands to `0..255`.
- Future versions can extend constants and opcodes while preserving the versioned header.
