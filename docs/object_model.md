# recorz Object Model (v0)

## Core model

- All runtime values are objects.
- Objects contain slots (name -> value) and a parent link for delegation.
- New objects are created by cloning existing objects.

## Slot categories

- Data slot: readable via message (e.g. `x`).
- Assignment slot: writable via corresponding setter message (e.g. `x:`).
- Method slot: callable behavior object (block/method closure).

Slot category is a protocol-level convention; runtime stores generic entries.

## Message lookup

1. Look for selector in receiver slots.
2. If missing, follow parent link and repeat.
3. If chain ends, send `doesNotUnderstand:` to original receiver.

## `self` and `super`

- `self` is lexical receiver bound at method activation.
- `super` means: start lookup at lexical parent of the method holder, but keep original receiver as `self`.

Because this is prototype-based, "method holder" is the object providing the matched slot during lookup.

## Method activation

Activation record contains:
- receiver (`self`)
- selector
- arguments
- lexical home context (for block non-local returns)
- sender link (for debugger traversal)

## Blocks and non-local return

- Block closes over lexical variables and `self`.
- `^expr` in a block returns from the home method activation (Smalltalk semantics).
- If home activation is no longer valid, raise `CannotReturn`.

## Cascades

- In `obj m1; m2: x; m3`, all cascaded messages target the original `obj`.
