# recorz Design Decisions (v0)

This document resolves initial architecture barriers and records the implications.

## DD-0001: Method `self` is lexical (Smalltalk-style)

Decision:
- `self` and `super` are pseudo-variables in executable code.
- `self` is not passed as an explicit block parameter in method bodies.
- Blocks used to define methods run with lexical access to `self` from the method activation.

Why:
- Matches your preferred Smalltalk mental model.
- Avoids two competing calling conventions (`do: [ :self | ... ]` vs lexical receiver).

Implications:
- `:self` is invalid because `self` is reserved and non-bindable.
- Method/block activation records must capture receiver and home context for non-local returns.
- `addMethod:do:` accepts a block whose explicit arguments are only method arguments (not receiver).

## DD-0002: No `thisContext` keyword in core language

Decision:
- `thisContext` is removed from core syntax.
- Debugging and reflection are exposed via objects/messages (mirror/context protocol), not a built-in pseudo-variable.

Why:
- Keeps syntax minimal.
- Avoids committing to a concrete context object model too early.

Implications:
- The VM still needs activation/context objects internally.
- Debugger can expose `Process currentContext` and context traversal messages via primitives.
- Reflection is still possible, but lives in libraries and tools.

## DD-0003: Primitive table model (numeric IDs)

Decision:
- Keep Smalltalk-like numeric primitive declarations: `<primitive: N>`.
- Start with primitive IDs in range `0..255`.

Why:
- Proven bootstrap path for small VM kernels.
- Easy to dispatch from RISC-V assembly.

Implications:
- A separate ABI document must define argument passing, return value, and failure behavior.
- Primitive failure contract: if primitive returns failure sentinel, method falls back to language code.
- Primitive IDs are part of image/runtime compatibility and need versioning discipline.

## DD-0004: Grammar simplification for parser stability

Decision:
- Simplified executable statement structure.
- Simplified top-level `Program` to one optional `ExecutableCode` unit.
- Tightened exponent syntax.

Why:
- Removes double-terminator edge cases and reduces parser ambiguity.
- Preserves minimal syntax while improving conformance testability.

Implications:
- Workspace/file evaluation is one executable chunk (statement sequence).
- If module/file composition is needed later, define it outside the core language grammar.

## Immediate follow-up specs to write

1. `docs/primitive_abi.md`
   - Primitive dispatch ABI, failure sentinel, side effects, trap policy.
2. `docs/object_model.md`
   - Slot lookup, delegation, `super` semantics in prototype chain.
3. `docs/debug_model.md`
   - Context object protocol and debugger hooks without `thisContext` keyword.
