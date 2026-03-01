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
- Integrated VM build pipeline to compile `vm/programs/smoke.rcz` into `vm/generated/program.bc`.
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
- Replaced block activation stubs with executable RBLK block payloads (`value`, `value:`) supporting lexical `self`, block argument references, integer constants, and sends.
- Wired dynamic method dispatch through executable block methods (`addMethod:do:` now runs method block bodies for unary and binary sends).
- Extended RBLK constant decoding/materialization to typed block constants (`int`, `symbol`, `string`) in both compiler and VM evaluator paths.
- Added bootstrap closure-reference support in RBLK (`PUSH_REF`) so block bodies can resolve captured/global refs via runtime bindings.
- Added general N-arity dynamic method execution by routing unresolved sends through block methods with indexed block arguments.
- Extended block evaluator `SEND` handling to route `argc>2` sends through dynamic method blocks, so method bodies can issue multi-keyword sends at runtime.
- Upgraded executable block payload format to `RBLK` v2 with lexical arg-ref metadata and nested block constants.
- Added runtime closure environments for nested block materialization, enabling non-global lexical capture of outer block arguments (by-value) through captured env chains.
- Added smoke/runtime coverage for closure-producing methods (`makeAdder:` -> block result) and captured-arg block execution.
- Added `RBLK` assignment opcode (`STORE_REF`) and block assignment encoding for reference updates.
- Added runtime captured-ref mutation path so closure bodies can update captured env references across invocations.
- Added smoke/runtime coverage for mutable closures (`makeCounter:` increments captured state).
- Added shared activation capture-env reuse so sibling closures created in one lexical activation share mutable captured state.
- Added smoke/runtime coverage for sibling closure sharing (`makeCounters:` yields `201`, `211`, `212` sequence).
- Added block-local variable support in `RBLK` (`local_count`, `PUSH_LOCAL`, `STORE_LOCAL`) with block-local assignment encoding.
- Added smoke/runtime coverage for block-local method execution (`localInc:`).
- Extended closure env construction/lookup/store to include block-local refs/values so nested closures can mutate outer block locals.
- Added smoke/runtime coverage for nested local capture mutation (`bumpLocal` yields `502`).
- Added `RBLK` non-local return opcode (`RETURN`) and block-statement return encoding (`^expr`) in executable block payloads.
- Added VM return-status unwind plumbing so nested block `^` escapes to enclosing method body and resolves as the method result at send boundary.
- Added home-method token tracking and active-frame validity checks for non-local returns.
- Added dedicated VM runtime program/test coverage for invalid escaped non-local return (`cannot_return.rcz` -> `CannotReturn` runtime value + clean shutdown).
- Replaced escaped-return string sentinel with a first-class `CannotReturn` runtime object prototype and dedicated print primitive.
- Added bootstrap `onCannotReturn:` protocol (`Object` pass-through + `CannotReturn` handler block dispatch) with QEMU runtime coverage.
- Added bootstrap `doesNotUnderstand:argc:` fallback on `Object` with selector/arity serial diagnostics and dedicated QEMU runtime coverage (`dnu.rcz`).
- Wired `doesNotUnderstand:argc:` fallback through block evaluator send failures so missing messages inside method/closure execution also report selector/arity and recover.
- Added VM image persistence v0 primitives (`saveImage`, `loadImage:`) with in-memory snapshot format covering globals, symbol tables, heap, and core runtime caches, plus QEMU restore coverage (`image.rcz`).
- Added serial host bridge primitives (`exportImage:`, `importImage`) with checksum bridge framing (`RCIMG <len> <sum32hex>`) and end-to-end QEMU roundtrip coverage (`image_host_export.rcz` -> host transfer -> `image_host_import.rcz`).
- Hardened cross-build image portability by moving `recorz_program_blob` into a dedicated linker section after VM state, and by snapshotting VM-owned symbol/block literal storage instead of relying on program-blob pointers.
- Added `scripts/qemu_image_bridge.py` host workflow utility to export bridge payloads into image files and import image files back into QEMU VM runs.
- Added language-visible convenience persistence primitives (`saveImageToHost`, `loadImageFromHost`) so image transfer/restore can be triggered directly from object protocol without manually chaining `saveImage`/`exportImage:` and `importImage`/`loadImage:`.
- Expanded parser conformance tests for nested object arrays, radix/scaled/float literals, and non-local returns in blocks.
- Upgraded executable block payload format to `RBLK` v3 with optional declared primitive ID metadata.
- Added VM runtime support for block/method primitive declarations (`<primitive: N>`) with Smalltalk-style fallback-to-body semantics when the primitive fails.
- Added smoke/runtime coverage for declared-primitive fallback execution (`primFallback` yields `444`).

Invariants changed:
- `self` is lexical and reserved.
- Context reflection is protocol-based, not keyword-based.
- Primitive ABI uses numeric IDs (`0..255`) with fallback behavior.

Known risks:
- Parser currently targets core syntax used by fixtures and tests; rare grammar corners may need extension.
- Bytecode format is host bootstrap IR, not final VM encoding.
- VM interpreter currently supports integer constants, reference bindings, integer/object prototype sends, slot-object storage, and primitive fallback; delegation semantics are still bootstrap-level and not yet image-object-model complete.
- RCBC v2 constant support currently covers integers, symbols, strings, floats, scaled-decimals, blocks, object-arrays, and byte-arrays.
- Block execution currently supports a bootstrap subset (lexical `self`, indexed arguments/locals, int/symbol/string/nested-block constants, optional declared primitive pre-dispatch, captured/global refs, `STORE_REF`/`STORE_LOCAL`, sends) via `RBLK` payloads; additional literal kinds and full closure semantics remain.
- Closure capture supports nested block capture of outer block arguments and block locals via runtime env objects, including mutation of captured refs inside closure bodies.
- Closure envs are shared across sibling closures from one lexical activation; deeper conformance coverage for mixed arg/local capture across multi-level nesting is still limited.
- Dynamic method dispatch executes block method bodies across selector arities (including multi-keyword selectors); richer context/debug semantics remain.
- Escaped non-local return now recovers to a first-class runtime `CannotReturn` object with `onCannotReturn:` handling; full image-level exception stack semantics are still pending.
- Message-miss fallback currently emits serial diagnostics and returns the receiver; structured debugger objects/stack snapshots are not implemented yet.
- Image persistence now supports serial host transfer (`exportImage:`/`importImage`) across QEMU restarts with checksum validation and a host-side file workflow, but transport is still raw UART text with no replay protection or in-VM disk/virtio backend.

Next acceptance criteria:
- Extend executable block payload support beyond int/symbol/string constants to full literal/object coverage.
- Add deeper closure-behavior tests (multi-level nesting, mixed arg/local capture, and post-closure outer-frame reads/writes).
- Add image-level exception protocol semantics around `CannotReturn` (handler install/unwind/resume policy) instead of VM-only recovery.
- Add durable host persistence backend(s) (file/virtio block) on top of the serial bridge.
