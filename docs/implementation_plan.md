# recorz Implementation Plan (macOS + QEMU)

## Target development environment

- Host OS: macOS
- Emulator: QEMU (`qemu-system-riscv64`)
- Initial VM implementation language: RISC-V assembly
- Early debug channel: UART serial console
- Graphics available from first boot milestone via framebuffer-backed device protocol

## Phase 0: Bootstrap repo and invariants (1 week)

Deliverables:
- `docs/architecture.md` with memory map and boot flow.
- `docs/primitive_abi.md` with primitive call contract.
- `docs/object_model.md` with prototype delegation rules.

Acceptance criteria:
- All core semantics decisions are written and internally consistent with grammar/examples.

## Phase 1: Hosted parser + bytecode format (2 weeks)

Deliverables:
- Lexer/parser conforming to `docs/recorz_ebnf.md`.
- AST tests including `docs/code_example.md`.
- Minimal bytecode format doc and encoder.

Acceptance criteria:
- Deterministic parse for literals, cascades, blocks, assignments, returns.

## Phase 2: RISC-V VM bring-up in QEMU (2-4 weeks)

Deliverables:
- Reset/startup code, trap vector, stack setup.
- Bytecode interpreter loop.
- UART debug output and panic diagnostics.
- Primitive dispatch table (`0..255`).

Acceptance criteria:
- VM boots under QEMU and executes a tiny precompiled program with serial output.

## Phase 3: Object runtime + image persistence (3-5 weeks)

Deliverables:
- Prototype object/slot representation.
- Message send + delegation lookup + inline cache v0.
- Closures, contexts, and non-local returns.
- Snapshot/restore image format v0.

Acceptance criteria:
- Save image, restart VM, continue execution from image state.

## Phase 4: Graphics + language-level drivers (3-6 weeks)

Deliverables:
- Framebuffer device protocol and draw primitives.
- Input/event primitives (keyboard/mouse or synthetic events first).
- Driver objects implemented in language where practical.

Acceptance criteria:
- Boot to a minimal graphical workspace while retaining serial debugger.

## Phase 5: Dev tools and reflective debugger (ongoing)

Deliverables:
- Inspector, browser, workspace, debugger objects.
- Context mirror protocol (without `thisContext` keyword).

Acceptance criteria:
- Breakpoint/step/inspect operations work in-language.

## Phase 6: FPGA migration planning (after software stability)

Deliverables:
- Profile-guided list of hardware acceleration candidates.
- ISA/μarch proposal for VM-assist instructions.

Acceptance criteria:
- FPGA softcore plan is traceable to measured VM bottlenecks.

## AI agent prompts

### 1) Spec agent
"Read `docs/recorz_ebnf.md`, `docs/design_decisions.md`, and draft/update `docs/object_model.md` with precise rules for slot lookup, delegation, `super`, method activation, and non-local return semantics. Include at least 12 executable examples and 10 edge-case tests."

### 2) Parser agent
"Implement a parser that conforms to `docs/recorz_ebnf.md`. Add parser tests for literals, block args, cascades, assignment chains, and return statements. Use `docs/code_example.md` as a fixture and produce an AST snapshot file in `docs/fixtures/`."

### 3) VM bootstrap agent
"Implement RISC-V assembly VM boot path for QEMU: reset handler, stack init, trap handler, UART logging, and interpreter loop skeleton. Add a script to run QEMU and verify a smoke program prints to serial."

### 4) Runtime agent
"Implement object memory layout, prototype slot lookup, message dispatch, block closures, and primitive dispatch table (`0..255`) per `docs/primitive_abi.md`. Include targeted tests for delegation and primitive fallback behavior."

### 5) Image persistence agent
"Implement image snapshot/restore v0. Persist heap objects, symbol table, global roots, and format version. Add corruption checks and an integration test that resumes execution after restart."

### 6) Docs/status agent
"Update `docs/status.md` after each merged milestone with: completed work, invariants changed, known risks, and next milestone acceptance criteria. Keep entries concise and date-stamped."

## Suggested working agreement for AI-assisted development

- Never change language semantics without updating `docs/design_decisions.md` first.
- Every runtime/VM change requires at least one corresponding test artifact.
- Keep primitives additive and versioned; avoid reusing primitive IDs.
- Keep serial debugging available even after graphics milestones.
