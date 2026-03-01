# recorz Architecture (Bootstrap)

## Boot flow (Phase 2)

1. QEMU `virt` loads kernel ELF at RAM base.
2. `_start` initializes stack and clears `.bss`.
3. Trap vector (`mtvec`) is set to `trap_handler`.
4. `vm_boot` prints boot diagnostics over UART.
5. Control enters `vm_interpreter_loop` and executes linked RCBC bytecode.

## Memory map assumptions (QEMU `virt`)

- RAM base: `0x80000000`
- UART0 (NS16550-compatible): `0x10000000`

## Runtime components in place

- Reset/startup path
- Trap handler
- UART output routines
- Primitive dispatch table (`0..255`)
- RCBC v2 bytecode interpreter loop (subset):
  - integer, symbol, string, float, scaled-decimal, block, object-array, and byte-array constants
  - global `LOAD_REF`/`STORE_REF`
  - tagged values (`int` immediates + object pointers)
  - prototype-chain method lookup for integer and object sends
  - bootstrap `Object` global with slot-object protocol primitives (`clone`, `addSlot:value:`, `slotNamed:`)
  - payload-backed protocols (`size`, `at:`, `at:put:`) for byte arrays, strings, and object arrays
  - executable block activation (`value`, `value:`) and dynamic method block execution for arbitrary send arity using compact `RBLK` payloads with block-local slots, bootstrap captured/global refs, nested lexical arg/local capture envs, and non-local return unwind
  - unary `print`
  - binary integer arithmetic (`+`, `-`, `*`, `/`)
  - primitive failure fallback through `primitiveFailed`
  - in-VM image snapshot/restore primitives (`saveImage`, `loadImage:`)
  - serial host bridge primitives for image transfer (`exportImage:`, `importImage`) with checksum framing plus language-level convenience wrappers (`saveImageToHost`, `loadImageFromHost`)
  - VM-owned symbol/block literal storage so persisted objects do not depend on transient program-blob pointers
  - linker layout that places `recorz_program_blob` after VM state sections to keep heap/root addresses stable across program rebuilds

## Next VM milestones

- Extend bytecode execution from subset to full hosted instruction set.
- Implement object memory model and root set.
- Integrate primitive ABI with message send/return and fallback conventions.
- Add durable host persistence backend(s) (file/virtio) and image integrity/version negotiation on top of the serial bridge.
