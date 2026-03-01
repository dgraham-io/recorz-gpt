# recorz Status

## 2026-02-28

Completed:
- Resolved initial language/runtime barriers and recorded decisions.
- Updated EBNF for lexical `self`/`super`, removed `thisContext` keyword, simplified statement/program shape.
- Added implementation roadmap and AI-agent prompt templates.
- Implemented Phase 1 hosted parser/AST/bytecode scaffold in Python.
- Added parser and bytecode tests.
- Implemented Phase 2 VM bootstrap in RISC-V assembly:
  - startup/reset, stack init, trap handler
  - UART serial output
  - primitive dispatch table (`0..255`)
  - interpreter loop skeleton
- Added QEMU build/run scripts and VM smoke test.
- Added RCBC v1 bytecode serialization from hosted compiler output.
- Integrated VM build pipeline to compile `vm/programs/smoke.rcz` into `vm/generated/smoke.bc`.
- Replaced interpreter placeholder with working bytecode fetch/decode/dispatch loop for a bootstrap subset.
- Extended VM smoke test to validate end-to-end bytecode execution output.
- Added VM support for global reference opcodes (`LOAD_REF`, `STORE_REF`) with assignment/read smoke coverage.
- Added VM support for binary integer arithmetic sends (`+`, `-`, `*`, `/`) with divide-by-zero diagnostics.
- Routed message sends through primitive dispatch (`print`, `+`, `-`, `*`, `/`) with VM-side primitive status handling.
- Added prototype-chain send lookup (`ProtoObject` -> `IntegerProto`) so selector resolution is delegation-based rather than hardcoded index matching.
- Added tagged value handling (`int` immediates + object pointers) in the bootstrap interpreter.
- Added bootstrap object primitives (`clone`, `addSlot:value:`, `slotNamed:`), slot-object access primitives (`name`, `value`, `value:`), and prebound `Object` global.
- Added VM-side primitive failure fallback path (`primitiveFailed`) and validated recovery in smoke (`x / 0` falls back without VM abort).
- Upgraded VM binary to RCBC v2 typed constants (int + symbol), added VM symbol interning, and migrated smoke slot naming to symbol literals (`#answer`).
- Extended RCBC v2 constants with string payloads, added VM string object construction for bytecode `LOAD_CONST`, and exercised this path in smoke (`'ok'` literal).
- Extended RCBC v2 constants with float and scaled-decimal payload kinds, added VM object construction for both constant forms, and exercised decode paths in smoke.
- Extended RCBC v2 constants with block/object-array/byte-array payload kinds, added VM object construction for these forms, and exercised decode paths in smoke.
- Added payload-backed protocol primitives (`size`, `at:`, `at:put:`) for strings/byte arrays/object arrays and block activation stubs (`value`, `value:`); exercised these paths in smoke output.
- Expanded parser conformance tests for nested object arrays, radix/scaled/float literals, and non-local returns in blocks.

Invariants changed:
- `self` is lexical and reserved.
- Context reflection is protocol-based, not keyword-based.
- Primitive ABI uses numeric IDs (`0..255`) with fallback behavior.

Known risks:
- Parser currently targets core syntax used by fixtures and tests; rare grammar corners may need extension.
- Bytecode format is host bootstrap IR, not final VM encoding.
- VM interpreter currently supports integer constants, reference bindings, integer/object prototype sends, slot-object storage, and primitive fallback; delegation semantics are still bootstrap-level and not yet image-object-model complete.
- RCBC v2 constant support currently covers integers, symbols, strings, floats, scaled-decimals, blocks, object-arrays, and byte-arrays.
- Block execution is still stubbed (`value`/`value:` do not execute captured bytecode yet).
- Method objects/user-defined method execution are still not wired into dispatch.

Next acceptance criteria:
- Implement non-stub block activation semantics and wire `addMethod:do:` so user-defined methods can execute via normal message dispatch.
